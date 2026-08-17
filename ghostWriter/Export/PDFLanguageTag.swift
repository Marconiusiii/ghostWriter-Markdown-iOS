//
//  PDFLanguageTag.swift
//  ghostWriter
//
//  Adds the document language to a finished PDF.
//
//  A tagged PDF must declare its language: without it a screen reader falls
//  back to its own default voice, which mispronounces the whole document when
//  that differs from what the document is written in, and a PDF/UA checker
//  reports the omission as a failure.
//
//  There is no Apple API that sets it. CGPDFContext accepts the languageText
//  tag property and silently discards it, offers no catalog key for it, and
//  PDFKit's document attributes cover only Title, Author, Subject, Keywords,
//  Creator, and Producer. So the attribute is added to the file afterwards.
//
//  The mechanism is PDF's own incremental update: the catalog object is
//  republished with /Lang added, followed by a small cross-reference section
//  chained to the original through /Prev. Nothing already in the file moves, so
//  every byte offset the original cross-reference table records stays valid —
//  which is why this is safe where editing the catalog in place is not.
//

import Foundation

nonisolated enum PDFLanguageTag {

    /// Returns `data` with `language` declared in its catalog, or `data`
    /// unchanged if the structure could not be read.
    ///
    /// Failing soft is deliberate: a PDF missing its language is a real but
    /// narrow accessibility fault, whereas a corrupted one cannot be read at
    /// all. If the file ever stops looking the way this expects, the export
    /// should degrade rather than break.
    static func adding(language: String, to data: Data) -> Data {
        guard let updated = incrementalUpdate(adding: language, to: data) else {
            return data
        }
        return updated
    }

    private static func incrementalUpdate(adding language: String, to data: Data) -> Data? {
        let bytes = [UInt8](data)

        guard let catalogMarker = bytes.firstRange(of: Array("/Type /Catalog".utf8)) else {
            return nil
        }

        // Walk back from the marker to the "N G obj" header that introduces the
        // catalog, so the replacement can reuse the same object number.
        guard let objectKeyword = bytes[..<catalogMarker.lowerBound]
            .lastRange(of: Array(" obj".utf8)) else { return nil }

        var lineStart = objectKeyword.lowerBound
        while lineStart > 0, bytes[lineStart - 1] != 0x0A, bytes[lineStart - 1] != 0x0D {
            lineStart -= 1
        }

        let header = String(decoding: bytes[lineStart..<objectKeyword.lowerBound], as: UTF8.self)
        let headerFields = header.split(separator: " ")
        guard headerFields.count >= 2,
              let objectNumber = Int(headerFields[0]),
              let generation = Int(headerFields[1]) else { return nil }

        guard let dictionaryBody = catalogBody(bytes, catalogMarker: catalogMarker) else {
            return nil
        }

        // A catalog that already declares a language is left alone.
        guard !dictionaryBody.contains("/Lang") else { return data }

        let text = String(decoding: data, as: UTF8.self)
        guard let trailer = lastTrailer(in: text),
              let previousOffset = lastStartXref(in: text) else { return nil }

        // /Size and /ID must carry over unchanged. An incremental update that
        // alters either breaks the chain back to the original table.
        let size = dictionaryValue("/Size", in: trailer).flatMap(Int.init)
            ?? (objectNumber + 1)
        let identifier = dictionaryValue("/ID", in: trailer).map { " /ID \($0)" } ?? ""
        let info = indirectReference("/Info", in: trailer).map { " /Info \($0)" } ?? ""

        var output = data
        if output.last != 0x0A { output.append(0x0A) }

        let objectOffset = output.count
        output.append(Data(
            "\(objectNumber) \(generation) obj\n<< \(dictionaryBody) /Lang (\(escape(language))) >>\nendobj\n".utf8
        ))

        // The cross-reference entry is a fixed 20-byte record: a ten-digit
        // offset, a five-digit generation, the in-use marker, and a two-byte
        // terminator.
        let xrefOffset = output.count
        var xref = "xref\n\(objectNumber) 1\n"
        xref += String(format: "%010d %05d n \n", objectOffset, generation)
        xref += "trailer\n"
        xref += "<< /Size \(size) /Root \(objectNumber) \(generation) R\(info)\(identifier)"
        xref += " /Prev \(previousOffset) >>\n"
        xref += "startxref\n\(xrefOffset)\n%%EOF\n"
        output.append(Data(xref.utf8))

        return output
    }

    /// Extracts the catalog dictionary's contents.
    ///
    /// The opening `<<` is found by scanning back from `/Type /Catalog`, then
    /// the matching close is found by balancing nested dictionaries. The
    /// balancing is essential: the catalog contains `/MarkInfo << /Marked true
    /// >>`, so taking the first `>>` yields a truncated catalog that silently
    /// drops /StructTreeRoot — the entire structure tree.
    private static func catalogBody(
        _ bytes: [UInt8],
        catalogMarker: Range<Int>
    ) -> String? {
        guard let open = bytes[..<catalogMarker.lowerBound]
            .lastRange(of: Array("<<".utf8)) else { return nil }

        var depth = 0
        var index = open.lowerBound
        var close: Int?

        while index < bytes.count - 1 {
            if bytes[index] == 0x3C, bytes[index + 1] == 0x3C {
                depth += 1
                index += 2
                continue
            }
            if bytes[index] == 0x3E, bytes[index + 1] == 0x3E {
                depth -= 1
                if depth == 0 {
                    close = index
                    break
                }
                index += 2
                continue
            }
            index += 1
        }

        guard let dictionaryEnd = close else { return nil }

        return String(decoding: bytes[(open.lowerBound + 2)..<dictionaryEnd], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lastTrailer(in text: String) -> String? {
        guard let range = text.range(of: "trailer", options: .backwards) else { return nil }
        return String(text[range.upperBound...])
    }

    private static func lastStartXref(in text: String) -> Int? {
        guard let range = text.range(of: "startxref", options: .backwards) else { return nil }
        let value = text[range.upperBound...]
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first?
            .trimmingCharacters(in: .whitespaces)
        return value.flatMap(Int.init)
    }

    /// Reads a simple or array-valued trailer entry.
    private static func dictionaryValue(_ key: String, in trailer: String) -> String? {
        guard let range = trailer.range(of: key) else { return nil }
        let remainder = trailer[range.upperBound...].drop { $0 == " " }

        if remainder.first == "[" {
            guard let end = remainder.firstIndex(of: "]") else { return nil }
            return String(remainder[...end])
        }

        return String(remainder.prefix { !$0.isWhitespace })
    }

    /// Reads an indirect reference, which is three tokens: "15 0 R".
    private static func indirectReference(_ key: String, in trailer: String) -> String? {
        guard let range = trailer.range(of: key) else { return nil }
        let tokens = trailer[range.upperBound...]
            .drop { $0 == " " }
            .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard tokens.count >= 3 else { return nil }
        return "\(tokens[0]) \(tokens[1]) \(tokens[2])"
    }

    /// Escapes the characters that are special inside a PDF literal string.
    private static func escape(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "(": escaped += "\\("
            case ")": escaped += "\\)"
            case "\\": escaped += "\\\\"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
