//
//  MarkdownRenderer.swift
//  ghostWriter
//
//  Turns markdown into HTML. The output is real, semantic HTML — actual h1
//  through h6, ul, ol, table, blockquote — because that is what lets VoiceOver
//  treat the rendered view as a structured document and navigate it with the
//  rotor. Producing correct semantics matters more here than producing pretty
//  markup.
//
//  Ported from the parser in the ghostWriter web app, with reference links,
//  task lists, and setext headings added.
//

import Foundation

enum MarkdownRenderer {

    /// Renders a complete markdown document to an HTML fragment.
    static func html(from markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        let definitions = extractLinkDefinitions(&lines)
        return renderBlocks(lines, baseIndent: 0, definitions: definitions)
    }

    // MARK: - Reference link definitions

    /// Pulls `[label]: url "title"` definitions out of the document. They are
    /// removed from the line array because they produce no visible output.
    private static func extractLinkDefinitions(_ lines: inout [String]) -> [String: String] {
        var definitions: [String: String] = [:]
        var remaining: [String] = []
        var insideCodeBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCodeBlock.toggle()
                remaining.append(line)
                continue
            }

            if !insideCodeBlock,
               let match = trimmed.firstMatch(of: /^\[([^\]]+)\]:\s*(\S+)(?:\s+["'(].*["')])?$/) {
                definitions[String(match.1).lowercased()] = String(match.2)
                continue
            }

            remaining.append(line)
        }

        lines = remaining
        return definitions
    }

    // MARK: - Block parsing

    private static func renderBlocks(
        _ lines: [String],
        baseIndent: Int,
        definitions: [String: String]
    ) -> String {
        var output = ""
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            let indent = LineAnalyzer.indentColumns(of: line)
            if indent < baseIndent { break }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let (fragment, next) = renderFencedCode(lines, from: index)
                output += fragment
                index = next
                continue
            }

            // ATX heading.
            if let level = LineAnalyzer.headingLevel(trimmed) {
                let raw = String(trimmed.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                output += "<h\(level)>\(inline(raw, definitions: definitions))</h\(level)>"
                index += 1
                continue
            }

            // Setext heading: text underlined with === or ---.
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                let isUnderline = !next.isEmpty
                    && (next.allSatisfy { $0 == "=" } || next.allSatisfy { $0 == "-" })
                if isUnderline && !LineAnalyzer.isHorizontalRule(trimmed) && ListMarker(line: line) == nil {
                    let level = next.first == "=" ? 1 : 2
                    output += "<h\(level)>\(inline(trimmed, definitions: definitions))</h\(level)>"
                    index += 2
                    continue
                }
            }

            if LineAnalyzer.isHorizontalRule(trimmed) {
                output += "<hr>"
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let (fragment, next) = renderBlockquote(lines, from: index, definitions: definitions)
                output += fragment
                index = next
                continue
            }

            if isTableStart(lines, at: index) {
                let (fragment, next) = renderTable(lines, from: index, definitions: definitions)
                output += fragment
                index = next
                continue
            }

            if ListMarker(line: line) != nil {
                let (fragment, next) = renderList(lines, from: index, definitions: definitions)
                output += fragment
                index = next
                continue
            }

            let (fragment, next) = renderParagraph(lines, from: index, definitions: definitions)
            output += fragment
            index = next
        }

        return output
    }

    private static func renderFencedCode(_ lines: [String], from start: Int) -> (String, Int) {
        let opening = lines[start].trimmingCharacters(in: .whitespaces)
        let fence = opening.hasPrefix("~~~") ? "~~~" : "```"
        let language = String(opening.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)

        var body: [String] = []
        var index = start + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) { break }
            body.append(lines[index])
            index += 1
        }

        if index < lines.count { index += 1 }

        let classAttribute = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
        let code = escape(body.joined(separator: "\n"))
        return ("<pre><code\(classAttribute)>\(code)</code></pre>", index)
    }

    private static func renderBlockquote(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (String, Int) {
        var inner: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // A blank line inside a quote is kept so paragraphs separate,
                // but a blank line followed by non-quote text ends the quote.
                let nextIsQuote = index + 1 < lines.count
                    && lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">")
                if !nextIsQuote { break }
                inner.append("")
                index += 1
                continue
            }

            guard trimmed.hasPrefix(">") else { break }

            var stripped = Substring(trimmed).dropFirst()
            if stripped.first == " " { stripped = stripped.dropFirst() }
            inner.append(String(stripped))
            index += 1
        }

        let body = renderBlocks(inner, baseIndent: 0, definitions: definitions)
        return ("<blockquote>\(body)</blockquote>", index)
    }

    private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let current = lines[index].trimmingCharacters(in: .whitespaces)
        let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return current.contains("|") && LineAnalyzer.isTableDivider(next)
    }

    private static func renderTable(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (String, Int) {
        let headers = splitRow(lines[start])
        let alignments = splitRow(lines[start + 1]).map { cell -> String in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let leading = trimmed.hasPrefix(":")
            let trailing = trimmed.hasSuffix(":")
            if leading && trailing { return "center" }
            if trailing { return "right" }
            if leading { return "left" }
            return ""
        }

        func styleAttribute(_ column: Int) -> String {
            guard column < alignments.count, !alignments[column].isEmpty else { return "" }
            return " style=\"text-align:\(alignments[column])\""
        }

        var head = "<thead><tr>"
        for (column, cell) in headers.enumerated() {
            head += "<th scope=\"col\"\(styleAttribute(column))>\(inline(cell, definitions: definitions))</th>"
        }
        head += "</tr></thead>"

        var body = "<tbody>"
        var index = start + 2

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || !trimmed.contains("|") { break }

            body += "<tr>"
            for (column, cell) in splitRow(line).enumerated() {
                body += "<td\(styleAttribute(column))>\(inline(cell, definitions: definitions))</td>"
            }
            body += "</tr>"
            index += 1
        }

        body += "</tbody>"
        return ("<table>\(head)\(body)</table>", index)
    }

    private static func splitRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func renderList(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (String, Int) {
        guard let first = ListMarker(line: lines[start]) else { return ("", start + 1) }

        let isOrdered: Bool
        var startNumber = 1
        switch first.style {
        case .ordered(let number):
            isOrdered = true
            startNumber = number
        case .unordered:
            isOrdered = false
        }

        let baseIndent = LineAnalyzer.indentColumns(of: lines[start])
        let tag = isOrdered ? "ol" : "ul"
        var items: [String] = []
        var index = start
        var containsTasks = false

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // A blank line only ends the list if the next content is not a
                // deeper or equal list item.
                var lookahead = index + 1
                while lookahead < lines.count,
                      lines[lookahead].trimmingCharacters(in: .whitespaces).isEmpty {
                    lookahead += 1
                }
                guard lookahead < lines.count,
                      ListMarker(line: lines[lookahead]) != nil,
                      LineAnalyzer.indentColumns(of: lines[lookahead]) >= baseIndent else { break }
                index = lookahead
                continue
            }

            let indent = LineAnalyzer.indentColumns(of: line)
            if indent < baseIndent { break }

            guard let marker = ListMarker(line: line), indent == baseIndent else { break }

            // Mixing bullets and numbers starts a new list.
            let sameStyle: Bool
            switch (marker.style, isOrdered) {
            case (.ordered, true), (.unordered, false): sameStyle = true
            default: sameStyle = false
            }
            guard sameStyle else { break }

            var body = inline(marker.content, definitions: definitions)

            if let box = marker.taskBox {
                containsTasks = true
                let checked = box.lowercased() == "[x]"
                let stateClass = checked ? " completed" : ""
                let status = checked ? "Completed:" : "Not completed:"
                // Rendered task lists are read-only. A styled indicator hidden
                // from accessibility gives sighted readers a consistent
                // checkbox while ordinary text conveys the same state reliably
                // to screen readers.
                body = "<span class=\"task-indicator\(stateClass)\" aria-hidden=\"true\"></span>"
                    + "<span class=\"task-status\">\(status)</span> "
                    + body
            }

            index += 1

            // Gather any deeper-indented lines as nested content.
            var nested: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                    let hasMore = index + 1 < lines.count
                        && LineAnalyzer.indentColumns(of: lines[index + 1]) > baseIndent
                    if !hasMore { break }
                    nested.append("")
                    index += 1
                    continue
                }
                guard LineAnalyzer.indentColumns(of: candidate) > baseIndent else { break }
                nested.append(candidate)
                index += 1
            }

            if !nested.isEmpty {
                body += renderBlocks(nested, baseIndent: 0, definitions: definitions)
            }

            let itemClass = marker.taskBox != nil ? " class=\"task-list-item\"" : ""
            items.append("<li\(itemClass)>\(body)</li>")
        }

        var attributes = ""
        if isOrdered && startNumber != 1 {
            attributes += " start=\"\(startNumber)\""
        }
        if containsTasks {
            attributes += " class=\"contains-task-list\""
        }

        return ("<\(tag)\(attributes)>\(items.joined())</\(tag)>", index)
    }

    private static func renderParagraph(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (String, Int) {
        var parts: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }

            // Any construct that starts its own block ends the paragraph.
            if index != start {
                if LineAnalyzer.headingLevel(trimmed) != nil
                    || LineAnalyzer.isHorizontalRule(trimmed)
                    || trimmed.hasPrefix(">")
                    || trimmed.hasPrefix("```")
                    || trimmed.hasPrefix("~~~")
                    || ListMarker(line: line) != nil {
                    break
                }
            }

            // Remove indentation used for paragraph layout, but preserve trailing
            // spaces because two or more of them are Markdown's hard-break
            // syntax.
            let paragraphText = String(line.drop { $0 == " " || $0 == "\t" })
            parts.append(paragraphText)
            index += 1
        }

        // A backslash or two trailing spaces means a hard line break.
        var rendered: [String] = []
        for (offset, part) in parts.enumerated() {
            var text = part
            var hardBreak = false
            if text.hasSuffix("\\") {
                text.removeLast()
                hardBreak = true
            } else if text.hasSuffix("  ") {
                text = text.trimmingCharacters(in: .whitespaces)
                hardBreak = true
            }
            var piece = inline(text, definitions: definitions)
            if hardBreak && offset < parts.count - 1 { piece += "<br>" }
            rendered.append(piece)
        }

        return ("<p>\(rendered.joined(separator: " "))</p>", index)
    }

    // MARK: - Inline parsing

    /// Handles emphasis, code, links, and images within a run of text.
    /// Inline code is extracted first and restored last so that markdown inside
    /// backticks is never interpreted.
    static func inline(_ text: String, definitions: [String: String] = [:]) -> String {
        var placeholders: [String] = []
        let withoutCode = extractCodeSpans(text, placeholders: &placeholders)
        let withoutFormatting = extractFormattingSpans(
            withoutCode,
            definitions: definitions,
            placeholders: &placeholders
        )
        var working = escape(withoutFormatting)

        working = replaceImagesAndLinks(working, definitions: definitions)

        for (offset, markup) in placeholders.enumerated() {
            working = working.replacingOccurrences(of: placeholder(offset), with: markup)
        }

        return working
    }

    private static func extractCodeSpans(
        _ text: String,
        placeholders: inout [String]
    ) -> String {
        var result = ""
        var remainder = Substring(text)
        while let opening = remainder.range(of: "`") {
            result += String(remainder[..<opening.lowerBound])
            let afterOpen = remainder[opening.upperBound...]
            guard let closing = afterOpen.range(of: "`") else {
                result += String(remainder[opening.lowerBound...])
                return result
            }
            let code = String(afterOpen[..<closing.lowerBound])
            result += placeholder(placeholders.count)
            placeholders.append("<code>\(escape(code))</code>")
            remainder = afterOpen[closing.upperBound...]
        }
        result += String(remainder)
        return result
    }

    private static func extractFormattingSpans(
        _ text: String,
        definitions: [String: String],
        placeholders: inout [String]
    ) -> String {
        let delimiters: [(opening: String, closing: String, element: String)] = [
            ("***", "***", "strong-emphasis"),
            ("___", "___", "strong-emphasis"),
            ("**", "**", "strong"),
            ("__", "__", "strong"),
            ("~~", "~~", "del"),
            ("<u>", "</u>", "u"),
            ("*", "*", "em"),
            ("_", "_", "em")
        ]
        var result = ""
        var remainder = Substring(text)

        while !remainder.isEmpty {
            let candidates = delimiters.compactMap { delimiter -> (Substring.Index, String, String, String)? in
                guard let range = openingRange(for: delimiter.opening, in: remainder) else { return nil }
                return (range.lowerBound, delimiter.opening, delimiter.closing, delimiter.element)
            }
            guard let candidate = candidates.min(by: { $0.0 < $1.0 }) else {
                result += String(remainder)
                break
            }

            let (openingIndex, opening, closing, element) = candidate
            result += String(remainder[..<openingIndex])
            let openingEnd = remainder.index(openingIndex, offsetBy: opening.count)
            let afterOpen = remainder[openingEnd...]
            guard let closeRange = closingRange(
                for: closing,
                in: afterOpen
            ), !afterOpen[..<closeRange.lowerBound].isEmpty else {
                result.append(remainder[openingIndex])
                remainder = remainder[remainder.index(after: openingIndex)...]
                continue
            }

            let inner = String(afterOpen[..<closeRange.lowerBound])
            let renderedInner = inline(inner, definitions: definitions)
            let markup: String
            switch element {
            case "strong-emphasis":
                markup = "<strong><em>\(renderedInner)</em></strong>"
            case "strong":
                markup = "<strong>\(renderedInner)</strong>"
            case "em":
                markup = "<em>\(renderedInner)</em>"
            case "del":
                markup = "<del>\(renderedInner)</del>"
            default:
                markup = "<u>\(renderedInner)</u>"
            }
            result += placeholder(placeholders.count)
            placeholders.append(markup)
            remainder = afterOpen[closeRange.upperBound...]
        }
        return result
    }

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

    private static func openingRange(
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
            let previousIsWord = delimiter == "_"
                && index > text.startIndex
                && isWordCharacter(text[text.index(before: index)])
            let next = text.index(after: index)
            let followedByWhitespace = next == text.endIndex || text[next].isWhitespace
            let adjacentMarker = (index > text.startIndex && text[text.index(before: index)] == marker)
                || (next < text.endIndex && text[next] == marker)
            if !previousIsWord && !followedByWhitespace && !adjacentMarker {
                return index..<next
            }
            searchIndex = next
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func placeholder(_ offset: Int) -> String {
        "\u{0}INLINE\(offset)\u{0}"
    }

    private static func replaceImagesAndLinks(
        _ text: String,
        definitions: [String: String]
    ) -> String {
        var result = text

        // Inline image: ![alt](src)
        result = result.replacing(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) { match in
            "<img src=\"\(match.2)\" alt=\"\(match.1)\">"
        }

        // Reference image: ![alt][label]
        result = result.replacing(/!\[([^\]]*)\]\[([^\]]*)\]/) { match in
            let label = match.2.isEmpty ? String(match.1) : String(match.2)
            guard let source = definitions[label.lowercased()] else { return String(match.0) }
            return "<img src=\"\(source)\" alt=\"\(match.1)\">"
        }

        // Inline link: [text](href)
        result = result.replacing(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) { match in
            "<a href=\"\(match.2)\">\(match.1)</a>"
        }

        // Reference link: [text][label]
        result = result.replacing(/\[([^\]]+)\]\[([^\]]*)\]/) { match in
            let label = match.2.isEmpty ? String(match.1) : String(match.2)
            guard let href = definitions[label.lowercased()] else { return String(match.0) }
            return "<a href=\"\(href)\">\(match.1)</a>"
        }

        // Bare autolink: <https://example.com>
        result = result.replacing(/&lt;(https?:\/\/[^\s&]+)&gt;/) { match in
            "<a href=\"\(match.1)\">\(match.1)</a>"
        }

        return result
    }

    /// Escapes text for safe inclusion in HTML. Applied to every piece of user
    /// content before it reaches the web view, so a document containing markup
    /// is displayed rather than executed.
    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
