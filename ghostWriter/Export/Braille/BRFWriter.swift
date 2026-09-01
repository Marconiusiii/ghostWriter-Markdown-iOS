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

import Foundation

nonisolated enum BRFWriter {

    /// Page geometry. The defaults use the common 40-cell by 25-line page.
    struct PageSetup: Equatable, Sendable {
        var cellsPerLine: Int = 40
        var linesPerPage: Int = 25

        static let standard = PageSetup()
    }

    struct RenderedBlock: Equatable, Sendable {
        var lines: [String]
        var isHeading: Bool
    }

    static func write(
        markdown: String,
        title: String,
        grade: BrailleGrade,
        pageSetup: PageSetup = .standard,
        translator: BrailleTranslator,
        documentLanguage: String = DocumentLanguage.resolvedTag("")
    ) async throws -> Data {
        let document = MarkdownDocumentParser.parse(markdown)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        var renderedBlocks: [RenderedBlock] = []

        // The title is set apart as a centered heading.
        if !trimmedTitle.isEmpty {
            let braille = try await translator.translate(trimmedTitle, grade: grade)
            var titleLines = centered(
                try asciiBraille(braille),
                width: pageSetup.cellsPerLine
            )
            titleLines.append("")
            renderedBlocks.append(RenderedBlock(lines: titleLines, isHeading: true))
        }

        for (index, block) in document.blocks.enumerated() {
            if index == 0,
               !trimmedTitle.isEmpty,
               case .heading(_, let content) = block,
               content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedTitle) == .orderedSame {
                continue
            }
            let rendered = try await render(
                block: block,
                grade: grade,
                pageSetup: pageSetup,
                translator: translator,
                listDepth: 0,
                listRunover: nil
            )
            let isHeading: Bool
            if case .heading = block {
                isHeading = true
            } else {
                isHeading = false
            }
            renderedBlocks.append(RenderedBlock(lines: rendered, isHeading: isHeading))
        }

        assert(
            renderedBlocks.flatMap(\.lines)
                .allSatisfy { $0.count <= pageSetup.cellsPerLine },
            "BRF layout produced a line wider than its configured page."
        )

        let paginated = paginate(
            renderedBlocks,
            linesPerPage: pageSetup.linesPerPage
        )
        return Data(paginated.utf8)
    }

    // MARK: - Blocks

    private static func render(
        block: ExportBlock,
        grade: BrailleGrade,
        pageSetup: PageSetup,
        translator: BrailleTranslator,
        listDepth: Int,
        listRunover: Int?
    ) async throws -> [String] {
        let width = pageSetup.cellsPerLine

        switch block {
        case .heading(let level, let content):
            let text = try await translate(content, grade: grade, translator: translator)
            guard !text.isEmpty else { return [] }

            // Use a consistent three-tier heading hierarchy.
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
            let text = try await translate(content, grade: grade, translator: translator)
            guard !text.isEmpty else { return [] }
            // 3-1: first line in cell 3, runover in cell 1.
            return wrapped(text, width: width, start: 2, runover: 0)

        case .list(let list):
            let commonRunover = listRunover
                ?? (listDepth + deepestLevel(in: list)) * 2
            var out: [String] = listDepth == 0 ? [""] : []
            for (offset, item) in list.items.enumerated() {
                let markerBraille: String
                if list.isOrdered {
                    markerBraille = try asciiBraille(
                        try await translate(
                            "\(list.start + offset).",
                            grade: grade,
                            translator: translator
                        )
                    )
                } else {
                    // BANA's primary bullet is dots 456, 256, represented as
                    // `_4` in Braille ASCII. A translated print hyphen is not a
                    // bullet and can defeat list recognition during reflow.
                    markerBraille = "_4"
                }
                var parts: [String] = []
                if let state = item.taskState {
                    parts.append(try asciiBraille(
                        try await translator.translate(
                            state.spokenPrefix(for: grade.languageTag),
                            grade: grade
                        )
                    ))
                }
                let itemText = try await translate(
                    item.content,
                    grade: grade,
                    translator: translator
                )
                if !itemText.isEmpty { parts.append(itemText) }
                let body = parts.joined(separator: " ")
                // Every level shares the runover determined by the deepest
                // level in this list section: 1-5 and 3-5 for two levels, etc.
                let start = listDepth * 2
                out += wrapped(
                    "\(markerBraille) \(body)",
                    width: width,
                    start: start,
                    runover: commonRunover
                )

                for child in item.children {
                    out += try await render(
                        block: child,
                        grade: grade,
                        pageSetup: pageSetup,
                        translator: translator,
                        listDepth: listDepth + 1,
                        listRunover: commonRunover
                    )
                }
            }
            if listDepth == 0 { out.append("") }
            return out

        case .blockQuote(let blocks):
            // Displayed material sits two cells in from the surrounding text.
            var out: [String] = [""]
            let nestedSetup = PageSetup(
                cellsPerLine: max(width - 2, 1),
                linesPerPage: pageSetup.linesPerPage
            )
            for inner in blocks {
                let rendered = try await render(
                    block: inner,
                    grade: grade,
                    pageSetup: nestedSetup,
                    translator: translator,
                    listDepth: listDepth,
                    listRunover: listRunover
                )
                out += rendered.map { $0.isEmpty ? $0 : "  " + $0 }
            }
            out.append("")
            return out

        case .codeBlock(_, let code):
            let fixedCellCode = code.replacingOccurrences(of: "\t", with: "    ")
            let text = try asciiBraille(
                try await translator.translate(
                    EBrailleWriter.TranslationTable.styledInput(fixedCellCode, adding: .noContract),
                    grade: grade
                )
            )
            guard !text.isEmpty else { return [] }
            var out: [String] = [""]
            // Code keeps its own line breaks rather than reflowing.
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                out += wrappedPreformatted(String(line), width: width, margin: 2)
            }
            out.append("")
            return out

        case .thematicBreak:
            // Markdown supplies no information about which braille separator
            // the author intended. Blank-line separation is accurate and does
            // not invent a full-width symbol sequence.
            return [""]

        case .table(let table):
            // Tables become a labelled list: a braille reader on a 40-cell
            // display cannot reliably follow wide visual columns.
            var out: [String] = [""]
            var headers: [String] = []
            for header in table.headers {
                headers.append(try await translate(header, grade: grade, translator: translator))
            }
            let separator = try asciiBraille(
                try await translator.translate(": ", grade: grade)
            )
            for (rowIndex, row) in table.rows.enumerated() {
                let rowHeading = try asciiBraille(
                    try await translator.translate(
                        grade.languageTag == "es"
                            ? "Fila \(rowIndex + 1)"
                            : "Row \(rowIndex + 1)",
                        grade: grade
                    )
                )
                out += wrapped(rowHeading, width: width, start: 0, runover: 2)
                var cells: [String] = []
                for cell in row {
                    cells.append(try await translate(cell, grade: grade, translator: translator))
                }
                for (index, cell) in cells.enumerated() {
                    let label = index < headers.count ? headers[index] : ""
                    let line = label.isEmpty ? cell : "\(label)\(separator)\(cell)"
                    out += wrapped(line, width: width, start: 2, runover: 4)
                }
                out.append("")
            }
            return out
        }
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

    private static func translate(
        _ spans: [ExportInline],
        grade: BrailleGrade,
        translator: BrailleTranslator
    ) async throws -> String {
        var result = ""
        for unit in EBrailleWriter.TranslationTable.inlineUnits(spans) {
            switch unit {
            case .text(let input), .link(_, let input):
                result += try asciiBraille(try await translator.translate(input, grade: grade))
            case .image(let image):
                if let alternative = image.alternativeText {
                    let prefix: String
                    if grade.languageTag == "es" {
                        prefix = image.isTactile ? "Gráfico táctil: " : "Imagen: "
                    } else {
                        prefix = image.isTactile ? "Tactile graphic: " : "Image: "
                    }
                    let description = try asciiBraille(
                        try await translator.translate(prefix + alternative, grade: grade)
                    )
                    result += description
                }
            case .lineBreak:
                result += "\n"
            }
        }
        return result
    }

    // MARK: - Layout

    /// Wraps text to the page width at a start cell and a runover cell.
    ///
    /// Cells are zero-based here and one-based in braille layout notation, so 3-1 is
    /// `start: 2, runover: 0`.
    static func wrapped(
        _ text: String,
        width: Int,
        start: Int,
        runover: Int
    ) -> [String] {
        if text.contains("\n") {
            var lines: [String] = []
            for (index, segment) in text.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).enumerated() {
                if segment.isEmpty {
                    lines.append("")
                } else {
                    lines += wrapped(
                        String(segment),
                        width: width,
                        start: index == 0 ? start : runover,
                        runover: runover
                    )
                }
            }
            return lines
        }

        let words = text.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !words.isEmpty else { return [] }

        let safeWidth = max(width, 1)
        let firstMargin = min(max(start, 0), safeWidth - 1)
        let continuationMargin = min(max(runover, 0), safeWidth - 1)
        var lines: [String] = []
        var current = String(repeating: " ", count: firstMargin)
        var isEmptyLine = true

        for word in words {
            var remainder = word
            while !remainder.isEmpty {
                let separator = isEmptyLine ? "" : " "
                let available = safeWidth - current.count - separator.count
                if available <= 0 {
                    lines.append(current)
                    current = String(repeating: " ", count: continuationMargin)
                    isEmptyLine = true
                    continue
                }

                if remainder.count <= available {
                    current += separator + remainder
                    remainder = ""
                    isEmptyLine = false
                } else if !isEmptyLine {
                    lines.append(current)
                    current = String(repeating: " ", count: continuationMargin)
                    isEmptyLine = true
                } else {
                    let division = dividedPrefix(of: remainder, fitting: available)
                    lines.append(current + division.line)
                    remainder = division.remainder
                    current = String(repeating: " ", count: continuationMargin)
                    isEmptyLine = true
                }
            }
        }
        if !isEmptyLine { lines.append(current) }
        return lines
    }

    /// Divides the exceptional unspaced sequence that is wider than a complete
    /// braille line. Normal words are moved intact to the next line by
    /// `wrapped`. An existing hyphen is the preferred division point. When no
    /// hyphen fits, reserve the final cell for a braille word-division hyphen so
    /// the reader knows that the sequence continues on the next line.
    private static func dividedPrefix(
        of text: String,
        fitting available: Int
    ) -> (line: String, remainder: String) {
        precondition(!text.isEmpty)
        let safeAvailable = max(available, 1)
        let candidate = String(text.prefix(safeAvailable))

        if let hyphen = candidate.lastIndex(of: "-"), hyphen != candidate.startIndex {
            let end = candidate.index(after: hyphen)
            let line = String(candidate[..<end])
            return (line, String(text.dropFirst(line.count)))
        }

        // A one-cell layout has no room for both content and a division sign.
        // Consuming one cell still guarantees progress and valid page width.
        guard safeAvailable > 1 else {
            return (String(text.prefix(1)), String(text.dropFirst(1)))
        }

        let contentCount = safeAvailable - 1
        let line = String(text.prefix(contentCount)) + "-"
        return (line, String(text.dropFirst(contentCount)))
    }

    /// Wraps preformatted material without collapsing indentation or repeated
    /// spaces. Code tokens may be wider than a physical line, so continuation
    /// is a mechanical slice rather than literary word wrapping.
    static func wrappedPreformatted(_ text: String, width: Int, margin: Int) -> [String] {
        let safeWidth = max(width, 1)
        let safeMargin = min(max(margin, 0), safeWidth - 1)
        let available = max(safeWidth - safeMargin, 1)
        if text.isEmpty { return [String(repeating: " ", count: safeMargin)] }

        var remainder = text[...]
        var lines: [String] = []
        while !remainder.isEmpty {
            let end = remainder.index(
                remainder.startIndex,
                offsetBy: min(available, remainder.count)
            )
            lines.append(
                String(repeating: " ", count: safeMargin) + String(remainder[..<end])
            )
            remainder = remainder[end...]
        }
        return lines
    }

    /// Centers a line when at least three blank cells fit on either side. Text
    /// too long to center is wrapped at the margin instead.
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
    static func paginate(_ blocks: [RenderedBlock], linesPerPage: Int) -> String {
        let allLines = blocks.flatMap(\.lines)
        guard linesPerPage > 0 else { return allLines.joined(separator: "\r\n") }

        var pages: [String] = []
        var page: [String] = []

        func finishPage() {
            guard !page.isEmpty else { return }
            pages.append(page.joined(separator: "\r\n"))
            page = []
        }

        func followingContentRequirement(after blockIndex: Int) -> Int {
            guard blockIndex + 1 < blocks.count else { return 0 }
            for following in blocks[(blockIndex + 1)...] {
                guard let firstContent = following.lines.firstIndex(where: { !$0.isEmpty }) else {
                    continue
                }
                let prefixCount = firstContent + 1
                // The general blank-line rule below keeps three lines when a
                // block begins with a separator, so reserve the same amount.
                return firstContent == 0 ? 1 : max(prefixCount, 3)
            }
            return 0
        }

        func append(_ line: String) {
            // Never open a page with a blank line: it wastes a line of a very
            // small page and reads as a missing heading.
            if page.isEmpty && line.isEmpty { return }
            // A separating blank line signals the start of a new block. Keep
            // room for that block's first line and at least one following line
            // instead of leaving a heading or list opening at the page bottom.
            if line.isEmpty, !page.isEmpty,
               linesPerPage - page.count < 3 {
                finishPage()
                return
            }
            page.append(line)
            if page.count == linesPerPage {
                finishPage()
            }
        }

        for (blockIndex, block) in blocks.enumerated() {
            if block.isHeading {
                // Avoid counting a previous block's trailing separators twice.
                while page.last?.isEmpty == true { page.removeLast() }

                let leadingBlankCount = block.lines.prefix { $0.isEmpty }.count
                let headingLineCount = block.lines.count
                    - (page.isEmpty ? leadingBlankCount : 0)
                let required = headingLineCount
                    + followingContentRequirement(after: blockIndex)

                // If the complete heading group fits on a fresh page but not
                // here, move it before rendering any of its wrapped lines.
                if !page.isEmpty,
                   required <= linesPerPage,
                   page.count + required > linesPerPage {
                    finishPage()
                }
            }

            for line in block.lines { append(line) }
        }
        finishPage()

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
        " A1B'K2L@CIF/MSP\"E3H9O6R^DJG>NTQ,*5<-U8V.%[$+X!&;:4\\0Z7(_?W]#Y)="
    )

    /// Converts Unicode braille patterns to the ASCII braille BRF requires.
    static func asciiBraille(_ braille: String) throws -> String {
        var output = ""
        output.reserveCapacity(braille.count)

        for character in braille.unicodeScalars {
            switch character.value {
            case 0x2800...0x283F:
                output.append(asciiTable[Int(character.value - 0x2800)])
            case 0x2840...0x28FF:
                throw BRFExportError.eightDotBrailleNotRepresentable
            case 0x0A, 0x0D:
                output.append("\n")
            case 0x20:
                output.append(" ")
            default:
                throw BRFExportError.unexpectedCharacter(character.value)
            }
        }
        return output
    }


    private static func deepestLevel(in list: ExportList) -> Int {
        var deepest = 1
        for item in list.items {
            for child in item.children {
                if case .list(let nested) = child {
                    deepest = max(deepest, 1 + deepestLevel(in: nested))
                }
            }
        }
        return deepest
    }
}

nonisolated enum BRFExportError: LocalizedError, Equatable, Sendable {
    case eightDotBrailleNotRepresentable
    case unexpectedCharacter(UInt32)

    var errorDescription: String? {
        switch self {
        case .eightDotBrailleNotRepresentable:
            return String(localized: "The translation contains eight-dot braille, which cannot be represented safely in BRF.")
        case .unexpectedCharacter(let value):
            return String(localized: "The translation contains a character that cannot be represented in BRF (Unicode \(String(value, radix: 16).uppercased())).")
        }
    }
}
