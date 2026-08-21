//
//  MarkdownInsertion.swift
//  ghostWriter
//
//  Pure text transformations for the editor's Insert actions. Keeping these
//  separate from the view makes Unicode selection behaviour and generated
//  syntax directly testable.
//

import Foundation

struct MarkdownInsertionResult: Equatable {
    let text: String
    let selection: TextSelection
}

enum MarkdownInsertionCommand: Equatable {
    case heading(level: Int)
    case link(label: String, address: String)
    case image(alternativeText: String, address: String)
    case tactileGraphic(description: String, address: String)
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case bulletedList
    case numberedList
    case taskList
    case table(columns: Int, rows: Int)
    case blockQuote
    case horizontalRule

    var confirmation: String {
        switch self {
        case .heading(let level):
            return String(localized: "Heading level \(min(max(1, level), 6)) applied.")
        case .link:
            return String(localized: "Link created.")
        case .image:
            return String(localized: "Image created.")
        case .tactileGraphic:
            return String(localized: "Tactile graphic attached.")
        case .bold:
            return String(localized: "Bold applied.")
        case .italic:
            return String(localized: "Italics applied.")
        case .strikethrough:
            return String(localized: "Strikethrough applied.")
        case .inlineCode:
            return String(localized: "Inline code applied.")
        case .codeBlock:
            return String(localized: "Code block created.")
        case .bulletedList:
            return String(localized: "Bulleted list created.")
        case .numberedList:
            return String(localized: "Numbered list created.")
        case .taskList:
            return String(localized: "Task list created.")
        case .table(let columns, let rows):
            let safeColumns = min(max(1, columns), 12)
            let safeRows = min(max(2, rows), 20)
            return String(localized: "Table created, \(safeColumns) columns and \(safeRows) rows.")
        case .blockQuote:
            return String(localized: "Block quote applied.")
        case .horizontalRule:
            return String(localized: "Horizontal rule inserted.")
        }
    }
}

enum MarkdownInsertion {
    static func apply(
        _ command: MarkdownInsertionCommand,
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        switch command {
        case .heading(let level):
            return heading(level: level, in: text, selection: selection)
        case .link(let label, let address):
            return link(
                in: text,
                selection: selection,
                label: label,
                address: address
            )
        case .image(let alternativeText, let address):
            return image(
                in: text,
                selection: selection,
                alternativeText: alternativeText,
                address: address
            )
        case .tactileGraphic(let description, let address):
            return tactileGraphic(
                in: text,
                selection: selection,
                description: description,
                address: address
            )
        case .bold:
            return bold(in: text, selection: selection)
        case .italic:
            return italic(in: text, selection: selection)
        case .strikethrough:
            return strikethrough(in: text, selection: selection)
        case .inlineCode:
            return inlineCode(in: text, selection: selection)
        case .codeBlock:
            return codeBlock(in: text, selection: selection)
        case .bulletedList:
            return bulletedList(in: text, selection: selection)
        case .numberedList:
            return numberedList(in: text, selection: selection)
        case .taskList:
            return taskList(in: text, selection: selection)
        case .table(let columns, let rows):
            return table(
                columns: columns,
                rows: rows,
                in: text,
                selection: selection
            )
        case .blockQuote:
            return blockQuote(in: text, selection: selection)
        case .horizontalRule:
            return horizontalRule(in: text, selection: selection)
        }
    }

    static func selectedText(in text: String, selection: TextSelection) -> String {
        let range = safeRange(in: text, selection: selection)
        return String(text[range])
    }

    static func link(
        in text: String,
        selection: TextSelection,
        label: String,
        address: String
    ) -> MarkdownInsertionResult {
        replaceSelection(
            in: text,
            selection: selection,
            with: "[\(escapeBracketText(label))](\(normalizeAddress(address)))"
        )
    }

    static func image(
        in text: String,
        selection: TextSelection,
        alternativeText: String,
        address: String
    ) -> MarkdownInsertionResult {
        replaceSelection(
            in: text,
            selection: selection,
            with: "![\(escapeBracketText(alternativeText))](\(normalizeAddress(address)))"
        )
    }

    static func tactileGraphic(
        in text: String,
        selection: TextSelection,
        description: String,
        address: String
    ) -> MarkdownInsertionResult {
        replaceSelection(
            in: text,
            selection: selection,
            with: "![\(escapeBracketText(description))](\(normalizeAddress(address)) \"tactile\")"
        )
    }

    static func bold(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        wrapInline(in: text, selection: selection, opening: "**", closing: "**")
    }

    static func italic(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        wrapInline(in: text, selection: selection, opening: "*", closing: "*")
    }

    static func strikethrough(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        wrapInline(in: text, selection: selection, opening: "~~", closing: "~~")
    }

    static func inlineCode(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        wrapInline(in: text, selection: selection, opening: "`", closing: "`")
    }

    static func heading(
        level: Int,
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        let safeLevel = min(max(1, level), 6)
        return transformSelectedLines(in: text, selection: selection) { line, _ in
            let content = line.replacing(
                /^#{1,6}(?:\s+|$)/,
                with: ""
            )
            return "\(String(repeating: "#", count: safeLevel)) \(content)"
        }
    }

    static func blockQuote(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        transformSelectedLines(in: text, selection: selection) { line, _ in
            "> \(line)"
        }
    }

    static func codeBlock(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        let selected = selectedText(in: text, selection: selection)
        let replacement = "```\n\(selected)\n```"
        let cursorOffset = selected.isEmpty ? 4 : replacement.count
        return replaceSelection(
            in: text,
            selection: selection,
            with: replacement,
            cursorOffset: cursorOffset
        )
    }

    static func bulletedList(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        transformSelectedLines(in: text, selection: selection) { line, _ in
            let (indent, content) = lineWithoutListMarker(line)
            return "\(indent)- \(content)"
        }
    }

    static func numberedList(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        transformSelectedLines(in: text, selection: selection) { line, index in
            let (indent, content) = lineWithoutListMarker(line)
            return "\(indent)\(index + 1). \(content)"
        }
    }

    static func taskList(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        transformSelectedLines(in: text, selection: selection) { line, _ in
            let (indent, content) = lineWithoutListMarker(line)
            return "\(indent)- [ ] \(content)"
        }
    }

    static func table(
        columns: Int,
        rows: Int,
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        let safeColumns = min(max(1, columns), 12)
        let safeRows = min(max(2, rows), 20)
        let headers = (1...safeColumns).map { "Column \($0)" }
        let headerRow = "| " + headers.joined(separator: " | ") + " |"
        let dividerRow = "| "
            + Array(repeating: "---", count: safeColumns)
                .joined(separator: " | ")
            + " |"
        let emptyRow = "| "
            + Array(repeating: "", count: safeColumns)
                .joined(separator: " | ")
            + " |"
        let bodyRows = Array(repeating: emptyRow, count: safeRows - 1)
        let table = ([headerRow, dividerRow] + bodyRows)
            .joined(separator: "\n")

        let range = safeRange(in: text, selection: selection)
        let contentBefore = String(text[..<range.lowerBound])
        let contentAfter = String(text[range.upperBound...])
        let leadingBreak: String
        if contentBefore.isEmpty || contentBefore.hasSuffix("\n\n") {
            leadingBreak = ""
        } else if contentBefore.hasSuffix("\n") {
            leadingBreak = "\n"
        } else {
            leadingBreak = "\n\n"
        }

        let trailingBreak: String
        if contentAfter.isEmpty || contentAfter.hasPrefix("\n\n") {
            trailingBreak = ""
        } else if contentAfter.hasPrefix("\n") {
            trailingBreak = "\n"
        } else {
            trailingBreak = "\n\n"
        }

        let replacement = leadingBreak + table + trailingBreak
        let firstCellOffset = leadingBreak.count
            + headerRow.count + 1
            + dividerRow.count + 1
            + 2
        return replaceSelection(
            in: text,
            selection: selection,
            with: replacement,
            cursorOffset: firstCellOffset
        )
    }

    static func horizontalRule(
        in text: String,
        selection: TextSelection
    ) -> MarkdownInsertionResult {
        let range = safeRange(in: text, selection: selection)
        let needsLeadingBreak = range.lowerBound > text.startIndex
            && text[text.index(before: range.lowerBound)] != "\n"
        let needsTrailingBreak = range.upperBound < text.endIndex
            && text[range.upperBound] != "\n"

        let replacement = "\(needsLeadingBreak ? "\n\n" : "")---\(needsTrailingBreak ? "\n\n" : "")"
        return replaceSelection(
            in: text,
            selection: selection,
            with: replacement
        )
    }

    private static func wrapInline(
        in text: String,
        selection: TextSelection,
        opening: String,
        closing: String
    ) -> MarkdownInsertionResult {
        let selected = selectedText(in: text, selection: selection)
        let replacement = opening + selected + closing
        let cursorOffset = selected.isEmpty ? opening.count : replacement.count
        return replaceSelection(
            in: text,
            selection: selection,
            with: replacement,
            cursorOffset: cursorOffset
        )
    }

    private static func replaceSelection(
        in text: String,
        selection: TextSelection,
        with replacement: String,
        cursorOffset: Int? = nil
    ) -> MarkdownInsertionResult {
        let range = safeRange(in: text, selection: selection)
        let location = text.distance(from: text.startIndex, to: range.lowerBound)
        var updated = text
        updated.replaceSubrange(range, with: replacement)

        return MarkdownInsertionResult(
            text: updated,
            selection: TextSelection(
                location: location + min(max(0, cursorOffset ?? replacement.count), replacement.count),
                length: 0
            )
        )
    }

    private static func transformSelectedLines(
        in text: String,
        selection: TextSelection,
        transform: (String, Int) -> String
    ) -> MarkdownInsertionResult {
        let selectionRange = safeRange(in: text, selection: selection)
        let lineStart = text[..<selectionRange.lowerBound].lastIndex(of: "\n")
            .map { text.index(after: $0) }
            ?? text.startIndex

        var lineEnd = selectionRange.upperBound
        if selection.length > 0,
           lineEnd > lineStart,
           text[text.index(before: lineEnd)] == "\n" {
            lineEnd = text.index(before: lineEnd)
        }
        while lineEnd < text.endIndex, text[lineEnd] != "\n" {
            lineEnd = text.index(after: lineEnd)
        }

        let original = String(text[lineStart..<lineEnd])
        let lines = original.split(separator: "\n", omittingEmptySubsequences: false)
        let replacement = lines.enumerated().map {
            transform(String($0.element), $0.offset)
        }.joined(separator: "\n")
        let location = text.distance(from: text.startIndex, to: lineStart)

        var updated = text
        updated.replaceSubrange(lineStart..<lineEnd, with: replacement)
        return MarkdownInsertionResult(
            text: updated,
            selection: TextSelection(
                location: location + replacement.count,
                length: 0
            )
        )
    }

    private static func lineWithoutListMarker(_ line: String) -> (String, String) {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var content = String(line.dropFirst(indent.count))
        content = content.replacing(
            /^(?:[-+*]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)/,
            with: ""
        )
        return (indent, content)
    }

    private static func safeRange(
        in text: String,
        selection: TextSelection
    ) -> Range<String.Index> {
        let location = min(max(0, selection.location), text.count)
        let length = min(max(0, selection.length), text.count - location)
        let start = text.index(text.startIndex, offsetBy: location)
        let end = text.index(start, offsetBy: length)
        return start..<end
    }

    private static func escapeBracketText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func normalizeAddress(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var disallowed = CharacterSet.whitespacesAndNewlines
        disallowed.formUnion(CharacterSet(charactersIn: "()<>"))
        let allowed = disallowed.inverted
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }
}
