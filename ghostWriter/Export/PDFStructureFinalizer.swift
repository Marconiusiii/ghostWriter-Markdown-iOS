//
//  PDFStructureFinalizer.swift
//  ghostWriter
//
//  Completes structure information that Core Graphics references but does not
//  serialize: the parent tree, each page's StructParents key, and Figure alt
//  text. The update is appended using PDF's incremental-update mechanism, so
//  the original page content and byte offsets remain untouched.
//

import Foundation

nonisolated enum PDFStructureFinalizer {
    static func finalizing(
        _ data: Data,
        figureAlternativeTexts: [String],
        actualTexts: [String]
    ) -> Data {
        incrementalUpdate(
            data,
            figureAlternativeTexts: figureAlternativeTexts,
            actualTexts: actualTexts
        ) ?? data
    }

    private struct PDFObject {
        let number: Int
        let generation: Int
        let body: String
    }

    private struct Replacement {
        let number: Int
        let generation: Int
        let body: String
    }

    private static func incrementalUpdate(
        _ data: Data,
        figureAlternativeTexts: [String],
        actualTexts: [String]
    ) -> Data? {
        let objects = dictionaryObjects(in: data)
        guard let structureRoot = objects.first(where: {
            hasName("StructTreeRoot", for: "Type", in: $0.body)
        }) else { return nil }

        let pages = objects.filter {
            hasName("Page", for: "Type", in: $0.body)
        }
        guard !pages.isEmpty else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        guard let trailer = lastTrailer(in: text),
              let previousOffset = lastStartXref(in: text),
              let rootReference = indirectReference("/Root", in: trailer)
        else { return nil }

        let oldSize = dictionaryValue("/Size", in: trailer).flatMap(Int.init)
            ?? ((objects.map(\.number).max() ?? 0) + 1)
        let parentTreeNumber = indirectReference(
            "/ParentTree",
            in: structureRoot.body
        ).flatMap { Int($0.split(separator: " ").first ?? "") } ?? oldSize

        let pageIndexByObject = Dictionary(
            uniqueKeysWithValues: pages.enumerated().map { ($0.element.number, $0.offset) }
        )
        var parentEntries = [[Int: String]](repeating: [:], count: pages.count)

        for object in objects where hasName("StructElem", for: "Type", in: object.body) {
            guard let pageReference = indirectReference("/Pg", in: object.body),
                  let pageNumber = Int(pageReference.split(separator: " ").first ?? ""),
                  let pageIndex = pageIndexByObject[pageNumber],
                  let markedContentID = integerValue("/K", in: object.body)
            else { continue }
            parentEntries[pageIndex][markedContentID] =
                "\(object.number) \(object.generation) R"
        }

        var replacements: [Replacement] = []
        for (index, page) in pages.enumerated() {
            replacements.append(Replacement(
                number: page.number,
                generation: page.generation,
                body: replacingInteger("/StructParents", with: index, in: page.body)
            ))
        }

        let numberTree = parentEntries.enumerated().map { pageIndex, entries in
            let maximum = entries.keys.max() ?? -1
            let references = maximum >= 0
                ? (0...maximum).map { entries[$0] ?? "null" }.joined(separator: " ")
                : ""
            return "\(pageIndex) [ \(references) ]"
        }.joined(separator: " ")
        replacements.append(Replacement(
            number: parentTreeNumber,
            generation: 0,
            body: "/Nums [ \(numberTree) ]"
        ))

        var rootBody = structureRoot.body
        rootBody = replacingReference(
            "/ParentTree",
            with: "\(parentTreeNumber) 0 R",
            in: rootBody
        )
        rootBody = replacingInteger(
            "/ParentTreeNextKey",
            with: pages.count,
            in: rootBody
        )
        rootBody = removingReference("/IDTree", from: rootBody)
        replacements.append(Replacement(
            number: structureRoot.number,
            generation: structureRoot.generation,
            body: rootBody
        ))

        let figures = objects.filter {
            hasName("StructElem", for: "Type", in: $0.body)
                && hasName("Figure", for: "S", in: $0.body)
        }
        for (figure, alternativeText) in zip(figures, figureAlternativeTexts) {
            replacements.append(Replacement(
                number: figure.number,
                generation: figure.generation,
                body: replacingPDFString(
                    "/Alt",
                    with: alternativeText,
                    in: figure.body
                )
            ))
        }

        // Core Graphics writes the Span structure elements but discards their
        // ActualText properties. Republish those leaves with Unicode text so
        // assistive technology does not have to reverse font-subset glyphs,
        // especially for right-to-left and non-Latin scripts.
        let spans = objects.filter {
            hasName("StructElem", for: "Type", in: $0.body)
                && hasName("Span", for: "S", in: $0.body)
        }
        for (span, actualText) in zip(spans, actualTexts) {
            replacements.append(Replacement(
                number: span.number,
                generation: span.generation,
                body: replacingPDFString(
                    "/ActualText",
                    with: actualText,
                    in: span.body
                )
            ))
        }

        var output = data
        if output.last != 0x0A { output.append(0x0A) }
        var offsets: [(number: Int, generation: Int, offset: Int)] = []
        for replacement in replacements.sorted(by: { $0.number < $1.number }) {
            offsets.append((replacement.number, replacement.generation, output.count))
            output.append(Data(
                "\(replacement.number) \(replacement.generation) obj\n<< \(replacement.body) >>\nendobj\n".utf8
            ))
        }

        let xrefOffset = output.count
        var xref = "xref\n"
        for group in contiguousGroups(offsets) {
            xref += "\(group[0].number) \(group.count)\n"
            for entry in group {
                xref += String(
                    format: "%010d %05d n \n",
                    entry.offset,
                    entry.generation
                )
            }
        }

        let newSize = max(
            oldSize,
            (replacements.map(\.number).max() ?? 0) + 1
        )
        let identifier = dictionaryValue("/ID", in: trailer).map { " /ID \($0)" } ?? ""
        let info = indirectReference("/Info", in: trailer).map { " /Info \($0)" } ?? ""
        xref += "trailer\n"
        xref += "<< /Size \(newSize) /Root \(rootReference)\(info)\(identifier)"
        xref += " /Prev \(previousOffset) >>\n"
        xref += "startxref\n\(xrefOffset)\n%%EOF\n"
        output.append(Data(xref.utf8))
        return output
    }

    private static func dictionaryObjects(in data: Data) -> [PDFObject] {
        let bytes = [UInt8](data)
        let objectMarker = Array(" obj".utf8)
        var objects: [Int: PDFObject] = [:]
        var searchStart = 0

        while searchStart < bytes.count,
              let marker = bytes[searchStart...].firstRange(of: objectMarker) {
            var headerStart = marker.lowerBound
            while headerStart > 0,
                  bytes[headerStart - 1] != 0x0A,
                  bytes[headerStart - 1] != 0x0D {
                headerStart -= 1
            }
            let header = String(
                decoding: bytes[headerStart..<marker.lowerBound],
                as: UTF8.self
            ).split(whereSeparator: \.isWhitespace)
            searchStart = marker.upperBound
            var bodyStart = marker.upperBound
            while bodyStart < bytes.count, isPDFWhitespace(bytes[bodyStart]) {
                bodyStart += 1
            }
            guard header.count == 2,
                  let number = Int(header[0]),
                  let generation = Int(header[1]),
                  bodyStart + 1 < bytes.count,
                  bytes[bodyStart] == 0x3C,
                  bytes[bodyStart + 1] == 0x3C,
                  let close = matchingDictionaryClose(bytes, openingAt: bodyStart)
            else { continue }

            let body = String(
                decoding: bytes[(bodyStart + 2)..<close],
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            objects[number] = PDFObject(
                number: number,
                generation: generation,
                body: body
            )
            searchStart = close + 2
        }

        return objects.values.sorted { $0.number < $1.number }
    }

    private static func isPDFWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x00 || byte == 0x09 || byte == 0x0A
            || byte == 0x0C || byte == 0x0D || byte == 0x20
    }

    private static func matchingDictionaryClose(
        _ bytes: [UInt8],
        openingAt open: Int
    ) -> Int? {
        var depth = 0
        var index = open
        while index < bytes.count - 1 {
            if bytes[index] == 0x3C, bytes[index + 1] == 0x3C {
                depth += 1
                index += 2
            } else if bytes[index] == 0x3E, bytes[index + 1] == 0x3E {
                depth -= 1
                if depth == 0 { return index }
                index += 2
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func hasName(
        _ value: String,
        for key: String,
        in body: String
    ) -> Bool {
        body.range(
            of: #"/\#(key)\s*/\#(value)(?![A-Za-z0-9])"#,
            options: .regularExpression
        ) != nil
    }

    private static func indirectReference(_ key: String, in value: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: key))\\s+(\\d+)\\s+(\\d+)\\s+R"
        guard let groups = captureGroups(pattern, in: value), groups.count == 2 else {
            return nil
        }
        return "\(groups[0]) \(groups[1]) R"
    }

    private static func integerValue(_ key: String, in value: String) -> Int? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: key))\\s+(\\d+)(?!\\s+\\d+\\s+R)"
        return captureGroups(pattern, in: value)?.first.flatMap(Int.init)
    }

    private static func captureGroups(_ pattern: String, in value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func replacingInteger(
        _ key: String,
        with value: Int,
        in body: String
    ) -> String {
        let pattern = "\(NSRegularExpression.escapedPattern(for: key))\\s+\\d+"
        if body.range(of: pattern, options: .regularExpression) != nil {
            return body.replacingOccurrences(
                of: pattern,
                with: "\(key) \(value)",
                options: .regularExpression
            )
        }
        return body + " \(key) \(value)"
    }

    private static func replacingReference(
        _ key: String,
        with reference: String,
        in body: String
    ) -> String {
        let pattern = "\(NSRegularExpression.escapedPattern(for: key))\\s+\\d+\\s+\\d+\\s+R"
        if body.range(of: pattern, options: .regularExpression) != nil {
            return body.replacingOccurrences(
                of: pattern,
                with: "\(key) \(reference)",
                options: .regularExpression
            )
        }
        return body + " \(key) \(reference)"
    }

    private static func removingReference(_ key: String, from body: String) -> String {
        body.replacingOccurrences(
            of: "\\s*\(NSRegularExpression.escapedPattern(for: key))\\s+\\d+\\s+\\d+\\s+R",
            with: "",
            options: .regularExpression
        )
    }

    private static func replacingPDFString(
        _ key: String,
        with value: String,
        in body: String
    ) -> String {
        let encoded = "<FEFF" + value.utf16.map {
            String(format: "%04X", $0)
        }.joined() + ">"
        let literalPattern = "\(NSRegularExpression.escapedPattern(for: key))\\s+(?:\\((?:\\\\.|[^)])*\\)|<[^>]*>)"
        if body.range(of: literalPattern, options: .regularExpression) != nil {
            return body.replacingOccurrences(
                of: literalPattern,
                with: "\(key) \(encoded)",
                options: .regularExpression
            )
        }
        return body + " \(key) \(encoded)"
    }

    private static func contiguousGroups(
        _ entries: [(number: Int, generation: Int, offset: Int)]
    ) -> [[(number: Int, generation: Int, offset: Int)]] {
        var groups: [[(number: Int, generation: Int, offset: Int)]] = []
        for entry in entries {
            if let last = groups.last?.last, entry.number == last.number + 1 {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }

    private static func lastTrailer(in text: String) -> String? {
        guard let range = text.range(of: "trailer", options: .backwards) else { return nil }
        return String(text[range.upperBound...])
    }

    private static func lastStartXref(in text: String) -> Int? {
        guard let range = text.range(of: "startxref", options: .backwards) else { return nil }
        let remainder = text[range.upperBound...]
        let lines = remainder.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let first = lines.first else { return nil }
        let value = first.trimmingCharacters(in: .whitespaces)
        return Int(value)
    }

    private static func dictionaryValue(_ key: String, in trailer: String) -> String? {
        guard let range = trailer.range(of: key) else { return nil }
        let remainder = trailer[range.upperBound...].drop { $0 == " " }
        if remainder.first == "[" {
            guard let end = remainder.firstIndex(of: "]") else { return nil }
            return String(remainder[...end])
        }
        return String(remainder.prefix { !$0.isWhitespace })
    }
}
