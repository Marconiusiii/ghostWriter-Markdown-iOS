//
//  BRFWriter.swift
//  ghostWriter
//
//  Writes Braille Ready Format, the format braille hardware actually reads.
//
//  eBraille is the better format — it reflows to whatever display it lands on,
//  and it carries structure a reader can navigate. But it was finalised in
//  August 2025, and device support is still arriving. The NLS eReader, among
//  others, reads BRF and PEF and does not yet know what a .ebrl file is.
//
//  BRF is much older and much dumber: ASCII braille, hard-wrapped to a fixed
//  line length, with form feeds between pages. Everything eBraille leaves to
//  the reading system — line length, page breaks, where a heading sits — has to
//  be decided here, at export time, because the file has no way to express a
//  preference. That is why the line width and page length are settings rather
//  than constants.
//
//  Layout follows BANA Braille Formats 2016, the same standard the eBraille
//  stylesheet implements, so a document exported both ways reads the same.
//

import Foundation

nonisolated enum BRFWriter {

    /// Page geometry. The defaults are the BANA standard for a braille page:
    /// 40 cells across, 25 lines down.
    struct PageSetup: Equatable, Sendable {
        var cellsPerLine: Int = 40
        var linesPerPage: Int = 25

        static let standard = PageSetup()
    }

    static func write(
        markdown: String,
        title: String,
        grade: BrailleGrade,
        pageSetup: PageSetup = .standard,
        translator: BrailleTranslator
    ) async throws -> Data {
        let document = MarkdownDocumentParser.parse(markdown)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []

        // The title is a centered heading, as BANA specifies for the start of
        // a work.
        if !trimmedTitle.isEmpty {
            let braille = try await translator.translate(trimmedTitle, grade: grade)
            lines += centered(asciiBraille(braille), width: pageSetup.cellsPerLine)
            lines.append("")
        }

        for block in document.blocks {
            lines += try await render(
                block: block,
                grade: grade,
                pageSetup: pageSetup,
                translator: translator,
                listDepth: 0
            )
        }

        let paginated = paginate(lines, linesPerPage: pageSetup.linesPerPage)
        return Data(paginated.utf8)
    }

    // MARK: - Blocks

    private static func render(
        block: ExportBlock,
        grade: BrailleGrade,
        pageSetup: PageSetup,
        translator: BrailleTranslator,
        listDepth: Int
    ) async throws -> [String] {
        let width = pageSetup.cellsPerLine

        switch block {
        case .heading(let level, let content):
            let text = asciiBraille(
                try await translate(content.plainText, grade: grade, translator: translator)
            )
            guard !text.isEmpty else { return [] }

            // BANA's heading hierarchy: centered, then cell 5, then cell 7.
            var out: [String] = [""]
            switch level {
            case 1:
                out += centered(text, width: width)
                out.append("")
            case 2:
                out += wrapped(text, width: width, start: 4, runover: 4)
            default:
                out += wrapped(text, width: width, start: 6, runover: 6)
            }
            return out

        case .paragraph(let content):
            let text = asciiBraille(
                try await translate(content.plainText, grade: grade, translator: translator)
            )
            guard !text.isEmpty else { return [] }
            // 3-1: first line in cell 3, runover in cell 1.
            return wrapped(text, width: width, start: 2, runover: 0)

        case .list(let list):
            var out: [String] = [""]
            for (offset, item) in list.items.enumerated() {
                let marker = list.isOrdered ? "\(list.start + offset)." : "-"
                let markerBraille = asciiBraille(
                    try await translate(marker, grade: grade, translator: translator)
                )
                let body = asciiBraille(
                    try await translate(
                        item.content.plainText, grade: grade, translator: translator
                    )
                )
                // 1-3 at the top level, each nested level two cells further.
                let start = listDepth * 2
                let runover = start + 2
                out += wrapped(
                    "\(markerBraille) \(body)",
                    width: width,
                    start: start,
                    runover: runover
                )

                for child in item.children {
                    out += try await render(
                        block: child,
                        grade: grade,
                        pageSetup: pageSetup,
                        translator: translator,
                        listDepth: listDepth + 1
                    )
                }
            }
            out.append("")
            return out

        case .blockQuote(let blocks):
            // Displayed material sits two cells in from the surrounding text.
            var out: [String] = [""]
            for inner in blocks {
                let rendered = try await render(
                    block: inner,
                    grade: grade,
                    pageSetup: pageSetup,
                    translator: translator,
                    listDepth: listDepth
                )
                out += rendered.map { $0.isEmpty ? $0 : "  " + $0 }
            }
            out.append("")
            return out

        case .codeBlock(_, let code):
            let text = asciiBraille(
                try await translate(code, grade: grade, translator: translator)
            )
            guard !text.isEmpty else { return [] }
            var out: [String] = [""]
            // Code keeps its own line breaks rather than reflowing.
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                out += wrapped(String(line), width: width, start: 2, runover: 2)
            }
            out.append("")
            return out

        case .thematicBreak:
            // A full line of dot-2-5 cells is BANA's separation line.
            return ["", String(repeating: "3", count: min(width, 40)), ""]

        case .table(let table):
            // Tables become a labelled list: a braille reader on a 40-cell
            // display cannot follow columns, and BANA's own guidance is to
            // linearize when a table will not fit.
            var out: [String] = [""]
            let headers = try await withTranslated(
                table.headers.map(\.plainText), grade: grade, translator: translator
            )
            for row in table.rows {
                let cells = try await withTranslated(
                    row.map(\.plainText), grade: grade, translator: translator
                )
                for (index, cell) in cells.enumerated() {
                    let label = index < headers.count ? headers[index] : ""
                    let line = label.isEmpty ? cell : "\(label): \(cell)"
                    out += wrapped(line, width: width, start: 0, runover: 2)
                }
                out.append("")
            }
            return out
        }
    }

    private static func withTranslated(
        _ strings: [String],
        grade: BrailleGrade,
        translator: BrailleTranslator
    ) async throws -> [String] {
        var out: [String] = []
        for string in strings {
            out.append(
                asciiBraille(try await translate(string, grade: grade, translator: translator))
            )
        }
        return out
    }

    private static func translate(
        _ text: String,
        grade: BrailleGrade,
        translator: BrailleTranslator
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return try await translator.translate(text, grade: grade)
    }

    // MARK: - Layout

    /// Wraps text to the page width at a start cell and a runover cell.
    ///
    /// Cells are zero-based here and one-based in BANA's notation, so 3-1 is
    /// `start: 2, runover: 0`.
    static func wrapped(
        _ text: String,
        width: Int,
        start: Int,
        runover: Int
    ) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var current = String(repeating: " ", count: start)
        var isEmptyLine = true
        var margin = start

        for word in words {
            let candidate = isEmptyLine ? word : " " + word
            if current.count + candidate.count <= width || isEmptyLine {
                current += candidate
                isEmptyLine = false
            } else {
                lines.append(current)
                margin = runover
                current = String(repeating: " ", count: margin) + word
            }
        }
        if !isEmptyLine { lines.append(current) }
        return lines
    }

    /// Centers a line, leaving at least three blank cells either side as BANA
    /// requires. Text too long to center is wrapped at the margin instead.
    static func centered(_ text: String, width: Int) -> [String] {
        guard text.count + 6 <= width else {
            return wrapped(text, width: width, start: 0, runover: 0)
        }
        let padding = (width - text.count) / 2
        return [String(repeating: " ", count: padding) + text]
    }

    /// Breaks the line stream into pages separated by form feeds.
    ///
    /// A form feed is how BRF marks a page break; without them the file is one
    /// continuous scroll and a reader loses any sense of position.
    static func paginate(_ lines: [String], linesPerPage: Int) -> String {
        guard linesPerPage > 0 else { return lines.joined(separator: "\r\n") }

        var pages: [String] = []
        var page: [String] = []

        for line in lines {
            // Never open a page with a blank line: it wastes a line of a very
            // small page and reads as a missing heading.
            if page.isEmpty && line.isEmpty { continue }
            page.append(line)
            if page.count == linesPerPage {
                pages.append(page.joined(separator: "\r\n"))
                page = []
            }
        }
        if !page.isEmpty { pages.append(page.joined(separator: "\r\n")) }

        // BRF uses CRLF line endings and a form feed between pages.
        return pages.joined(separator: "\r\n\u{000C}") + "\r\n"
    }

    // MARK: - ASCII braille

    /// The 64 ASCII braille characters, indexed by the low six bits of a
    /// Unicode braille pattern.
    ///
    /// BRF predates Unicode: it encodes each cell as a printable ASCII
    /// character from this fixed set, which is what braille embossers and
    /// hardware readers expect. The translation itself still happens in
    /// Unicode, so this is purely the final encoding step.
    /// Derived from liblouis's own `en-us-brf.dis` display table and verified
    /// character by character against `lou_translate`'s BRF output, rather
    /// than transcribed from a chart. A hand-copied table produces plausible
    /// nonsense: the first attempt at this had two cells wrong, which reads as
    /// valid braille and is silently the wrong word.
    private static let asciiTable = Array(
        " a1b'k2l`cif/msp\"e3h9o6r~djg>ntq,*5<-u8v.%{$+x!&;:4|0z7(_?w}#y)="
    )

    /// Converts Unicode braille patterns to the ASCII braille BRF requires.
    static func asciiBraille(_ braille: String) -> String {
        var output = ""
        output.reserveCapacity(braille.count)

        for character in braille.unicodeScalars {
            switch character.value {
            case 0x2800...0x283F:
                output.append(asciiTable[Int(character.value - 0x2800)])
            case 0x2840...0x28FF:
                // Eight-dot patterns have no BRF encoding. The low six dots
                // are the closest honest approximation.
                output.append(asciiTable[Int((character.value - 0x2800) & 0x3F)])
            case 0x0A, 0x0D:
                output.append("\n")
            default:
                output.unicodeScalars.append(character)
            }
        }
        return output
    }
}
