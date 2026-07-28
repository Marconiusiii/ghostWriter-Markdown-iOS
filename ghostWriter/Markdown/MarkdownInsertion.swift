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

enum MarkdownInsertion {
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
