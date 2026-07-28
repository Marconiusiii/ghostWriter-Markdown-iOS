//
//  MarkdownInsertion.swift
//  ghostWriter
//
//  Pure text transformations for the guided Link and Image insertion sheets.
//  Keeping these separate from the view makes Unicode selection behaviour and
//  generated syntax directly testable.
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

    private static func replaceSelection(
        in text: String,
        selection: TextSelection,
        with replacement: String
    ) -> MarkdownInsertionResult {
        let range = safeRange(in: text, selection: selection)
        let location = text.distance(from: text.startIndex, to: range.lowerBound)
        var updated = text
        updated.replaceSubrange(range, with: replacement)

        return MarkdownInsertionResult(
            text: updated,
            selection: TextSelection(
                location: location + replacement.count,
                length: 0
            )
        )
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
