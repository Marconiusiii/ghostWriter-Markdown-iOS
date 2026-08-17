//
//  MarkdownInlineParser.swift
//  ghostWriter
//
//  Parses inline markdown into nested ExportInline spans.
//
//  MarkdownRenderer handles the same job with placeholder substitution, which
//  works because its destination is a string. Here the destination is a tree,
//  so this recurses directly. Delimiter precedence matches the renderer's
//  ordering — triple markers before double before single — so emphasis is
//  interpreted the same way in every format.
//

import Foundation

nonisolated enum MarkdownInlineParser {

    static func parse(
        _ text: String,
        definitions: [String: String] = [:]
    ) -> [ExportInline] {
        merge(parseSpans(Substring(text), definitions: definitions))
    }

    private static func parseSpans(
        _ source: Substring,
        definitions: [String: String]
    ) -> [ExportInline] {
        var result: [ExportInline] = []
        var remainder = source
        var literal = ""

        func flushLiteral() {
            if !literal.isEmpty {
                result.append(.text(literal))
                literal = ""
            }
        }

        while !remainder.isEmpty {
            // A backslash escapes the character after it, which then carries no
            // markdown meaning.
            if remainder.first == "\\", remainder.count > 1 {
                remainder = remainder.dropFirst()
                literal.append(remainder.removeFirst())
                continue
            }

            // Inline code binds tighter than everything else — markdown inside
            // backticks is never interpreted.
            if remainder.first == "`" {
                let afterOpen = remainder.dropFirst()
                if let close = afterOpen.firstIndex(of: "`") {
                    flushLiteral()
                    result.append(.code(String(afterOpen[..<close])))
                    remainder = afterOpen[afterOpen.index(after: close)...]
                    continue
                }
            }

            if remainder.hasPrefix("!["),
               let parsed = parseImage(remainder, definitions: definitions) {
                flushLiteral()
                result.append(parsed.inline)
                remainder = parsed.remainder
                continue
            }

            if remainder.first == "[",
               let parsed = parseLink(remainder, definitions: definitions) {
                flushLiteral()
                result.append(parsed.inline)
                remainder = parsed.remainder
                continue
            }

            // Autolink: <https://example.com>
            if remainder.hasPrefix("<"),
               let close = remainder.firstIndex(of: ">") {
                let inner = String(remainder[remainder.index(after: remainder.startIndex)..<close])
                if inner.hasPrefix("http://") || inner.hasPrefix("https://") {
                    flushLiteral()
                    result.append(.link(destination: inner, content: [.text(inner)]))
                    remainder = remainder[remainder.index(after: close)...]
                    continue
                }
            }

            if remainder.hasPrefix("<u>"),
               let close = remainder.dropFirst(3).range(of: "</u>") {
                let afterOpen = remainder.dropFirst(3)
                flushLiteral()
                result.append(.underline(
                    parseSpans(afterOpen[..<close.lowerBound], definitions: definitions)
                ))
                remainder = afterOpen[close.upperBound...]
                continue
            }

            if let parsed = parseEmphasis(remainder, definitions: definitions) {
                flushLiteral()
                result.append(parsed.inline)
                remainder = parsed.remainder
                continue
            }

            literal.append(remainder.removeFirst())
        }

        flushLiteral()
        return result
    }

    // MARK: - Emphasis

    private static func parseEmphasis(
        _ remainder: Substring,
        definitions: [String: String]
    ) -> (inline: ExportInline, remainder: Substring)? {
        // Longest delimiters first, so *** is never read as * followed by **.
        let delimiters: [(marker: String, wrap: ([ExportInline]) -> ExportInline)] = [
            ("***", { .strong([.emphasis($0)]) }),
            ("___", { .strong([.emphasis($0)]) }),
            ("**", { .strong($0) }),
            ("__", { .strong($0) }),
            ("~~", { .strikethrough($0) }),
            ("*", { .emphasis($0) }),
            ("_", { .emphasis($0) })
        ]

        for (marker, wrap) in delimiters where remainder.hasPrefix(marker) {
            let afterOpen = remainder.dropFirst(marker.count)
            guard let close = closingRange(for: marker, in: afterOpen),
                  close.lowerBound != afterOpen.startIndex else { continue }

            let inner = afterOpen[..<close.lowerBound]
            return (
                wrap(parseSpans(inner, definitions: definitions)),
                afterOpen[close.upperBound...]
            )
        }

        return nil
    }

    /// Finds the closing delimiter. Single-character markers need the same
    /// intraword guards MarkdownRenderer applies, so that `snake_case_name`
    /// does not become emphasised text.
    private static func closingRange(
        for delimiter: String,
        in text: Substring
    ) -> Range<Substring.Index>? {
        guard delimiter == "*" || delimiter == "_" else {
            return text.range(of: delimiter)
        }

        let marker = Character(delimiter)
        var searchIndex = text.startIndex

        while searchIndex < text.endIndex,
              let index = text[searchIndex...].firstIndex(of: marker) {
            let previousIsMarker = index > text.startIndex
                && text[text.index(before: index)] == marker
            let next = text.index(after: index)
            let nextIsMarker = next < text.endIndex && text[next] == marker
            let precededByWhitespace = index == text.startIndex
                || text[text.index(before: index)].isWhitespace
            let followedByWord = delimiter == "_"
                && next < text.endIndex
                && isWordCharacter(text[next])

            if !previousIsMarker && !nextIsMarker && !precededByWhitespace && !followedByWord {
                return index..<next
            }
            searchIndex = next
        }

        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    // MARK: - Links and images

    private static func parseImage(
        _ remainder: Substring,
        definitions: [String: String]
    ) -> (inline: ExportInline, remainder: Substring)? {
        guard let label = bracketedRange(remainder, openingOffset: 2) else { return nil }
        let alt = String(remainder[label.inner])

        if let destination = destination(after: label.after, in: remainder, definitions: definitions, label: alt) {
            return (
                .image(ExportImage(
                    source: destination.value,
                    alternativeText: alt.isEmpty ? nil : unescape(alt)
                )),
                destination.remainder
            )
        }

        return nil
    }

    private static func parseLink(
        _ remainder: Substring,
        definitions: [String: String]
    ) -> (inline: ExportInline, remainder: Substring)? {
        guard let label = bracketedRange(remainder, openingOffset: 1) else { return nil }
        let text = String(remainder[label.inner])
        guard !text.isEmpty else { return nil }

        if let destination = destination(after: label.after, in: remainder, definitions: definitions, label: text) {
            return (
                .link(
                    destination: destination.value,
                    content: parseSpans(remainder[label.inner], definitions: definitions)
                ),
                destination.remainder
            )
        }

        return nil
    }

    /// Locates the matching `]` for a bracketed label, tracking nesting so a
    /// label containing brackets does not terminate early.
    private static func bracketedRange(
        _ text: Substring,
        openingOffset: Int
    ) -> (inner: Range<Substring.Index>, after: Substring.Index)? {
        guard text.count > openingOffset else { return nil }
        let start = text.index(text.startIndex, offsetBy: openingOffset)
        var depth = 1
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if character == "[" { depth += 1 }
            if character == "]" {
                depth -= 1
                if depth == 0 {
                    return (start..<index, text.index(after: index))
                }
            }
            index = text.index(after: index)
        }

        return nil
    }

    /// Resolves either an inline `(destination)` or a reference `[label]`
    /// following a bracketed label.
    private static func destination(
        after index: Substring.Index,
        in text: Substring,
        definitions: [String: String],
        label: String
    ) -> (value: String, remainder: Substring)? {
        guard index < text.endIndex else { return nil }

        if text[index] == "(" {
            let afterParen = text.index(after: index)
            guard let close = text[afterParen...].firstIndex(of: ")") else { return nil }
            var raw = String(text[afterParen..<close]).trimmingCharacters(in: .whitespaces)
            // Strip an optional title: (url "title")
            if let space = raw.firstIndex(where: { $0 == " " || $0 == "\t" }) {
                raw = String(raw[..<space])
            }
            return (raw, text[text.index(after: close)...])
        }

        if text[index] == "[" {
            guard let reference = bracketedRange(text[index...], openingOffset: 1) else { return nil }
            let key = String(text[index...][reference.inner])
            let lookup = (key.isEmpty ? label : key).lowercased()
            guard let resolved = definitions[lookup] else { return nil }
            return (resolved, text[index...][reference.after...])
        }

        // A shortcut reference: [label] with a matching definition.
        if let resolved = definitions[label.lowercased()] {
            return (resolved, text[index...])
        }

        return nil
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\\([\\`*_{}\[\]()<>#+\-.!|~])"#,
            with: "$1",
            options: .regularExpression
        )
    }

    /// Collapses adjacent plain-text spans so downstream layout measures whole
    /// words rather than a stream of single characters.
    private static func merge(_ spans: [ExportInline]) -> [ExportInline] {
        var result: [ExportInline] = []
        for span in spans {
            if case .text(let value) = span,
               case .text(let previous)? = result.last {
                result[result.count - 1] = .text(previous + value)
            } else {
                result.append(span)
            }
        }
        return result
    }
}
