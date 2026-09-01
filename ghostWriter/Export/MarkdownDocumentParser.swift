//
//  MarkdownDocumentParser.swift
//  ghostWriter
//
//  Parses markdown into ExportDocument. The block rules follow
//  MarkdownRenderer exactly — same heading forms, same fence handling, same
//  blank-line-ends-a-list behaviour — so a document exports the same shape it
//  renders. Where this differs is that nesting is preserved as structure rather
//  than flattened into a string.
//

import Foundation

nonisolated enum MarkdownDocumentParser {

    static func parse(_ markdown: String) -> ExportDocument {
        var lines = markdown.components(separatedBy: "\n")
        let definitions = extractLinkDefinitions(&lines)
        return ExportDocument(
            blocks: parseBlocks(lines, baseIndent: 0, definitions: definitions)
        )
    }

    // MARK: - Reference link definitions

    /// Pulls `[label]: url` definitions out of the document before parsing, the
    /// same way MarkdownRenderer does. They produce no visible output but every
    /// link and image referring to them needs the table.
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

    private static func parseBlocks(
        _ lines: [String],
        baseIndent: Int,
        definitions: [String: String]
    ) -> [ExportBlock] {
        var blocks: [ExportBlock] = []
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

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let (block, next) = parseFencedCode(lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            if let level = LineAnalyzer.headingLevel(trimmed) {
                let raw = String(trimmed.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(
                    level: level,
                    content: MarkdownInlineParser.parse(raw, definitions: definitions)
                ))
                index += 1
                continue
            }

            // Setext heading: text underlined with === or ---.
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                let isUnderline = !next.isEmpty
                    && (next.allSatisfy { $0 == "=" } || next.allSatisfy { $0 == "-" })
                if isUnderline && !LineAnalyzer.isHorizontalRule(trimmed) && ListMarker(line: line) == nil {
                    blocks.append(.heading(
                        level: next.first == "=" ? 1 : 2,
                        content: MarkdownInlineParser.parse(trimmed, definitions: definitions)
                    ))
                    index += 2
                    continue
                }
            }

            if LineAnalyzer.isHorizontalRule(trimmed) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let (block, next) = parseBlockQuote(lines, from: index, definitions: definitions)
                blocks.append(block)
                index = next
                continue
            }

            if isTableStart(lines, at: index) {
                let (block, next) = parseTable(lines, from: index, definitions: definitions)
                blocks.append(block)
                index = next
                continue
            }

            if ListMarker(line: line) != nil {
                let (block, next) = parseList(lines, from: index, definitions: definitions)
                blocks.append(block)
                index = next
                continue
            }

            let (block, next) = parseParagraph(lines, from: index, definitions: definitions)
            blocks.append(block)
            index = next
        }

        return blocks
    }

    private static func parseFencedCode(
        _ lines: [String],
        from start: Int
    ) -> (ExportBlock, Int) {
        let opening = lines[start].trimmingCharacters(in: .whitespaces)
        let fence = opening.hasPrefix("~~~") ? "~~~" : "```"
        let language = String(opening.dropFirst(fence.count))
            .trimmingCharacters(in: .whitespaces)

        var body: [String] = []
        var index = start + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) { break }
            body.append(lines[index])
            index += 1
        }

        if index < lines.count { index += 1 }

        return (
            .codeBlock(
                language: language.isEmpty ? nil : language,
                code: body.joined(separator: "\n")
            ),
            index
        )
    }

    private static func parseBlockQuote(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (ExportBlock, Int) {
        var inner: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
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

        return (
            .blockQuote(parseBlocks(inner, baseIndent: 0, definitions: definitions)),
            index
        )
    }

    private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let current = lines[index].trimmingCharacters(in: .whitespaces)
        let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return current.contains("|") && LineAnalyzer.isTableDivider(next)
    }

    private static func parseTable(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (ExportBlock, Int) {
        let headers = splitRow(lines[start]).map {
            MarkdownInlineParser.parse($0, definitions: definitions)
        }

        let alignments = splitRow(lines[start + 1]).map { cell -> ExportAlignment in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let leading = trimmed.hasPrefix(":")
            let trailing = trimmed.hasSuffix(":")
            if leading && trailing { return .center }
            if trailing { return .trailing }
            if leading { return .leading }
            return .natural
        }

        var rows: [[[ExportInline]]] = []
        var index = start + 2

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || !trimmed.contains("|") { break }
            rows.append(splitRow(lines[index]).map {
                MarkdownInlineParser.parse($0, definitions: definitions)
            })
            index += 1
        }

        return (
            .table(ExportTable(headers: headers, rows: rows, alignments: alignments)),
            index
        )
    }

    private static func splitRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func parseList(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (ExportBlock, Int) {
        guard let first = ListMarker(line: lines[start]) else {
            return (.paragraph([]), start + 1)
        }

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
        var items: [ExportListItem] = []
        var index = start

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

            var item = ExportListItem(
                content: MarkdownInlineParser.parse(marker.content, definitions: definitions)
            )

            if let box = marker.taskBox {
                item.taskState = box.lowercased() == "[x]" ? .completed : .notCompleted
            }

            index += 1

            // Gather deeper-indented lines as this item's nested content, then
            // parse them as blocks. This is where the tree comes from: a nested
            // list becomes a child block rather than an indent level on a flat
            // paragraph.
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
                item.children = parseBlocks(nested, baseIndent: 0, definitions: definitions)
            }

            items.append(item)
        }

        return (
            .list(ExportList(isOrdered: isOrdered, start: startNumber, items: items)),
            index
        )
    }

    private static func parseParagraph(
        _ lines: [String],
        from start: Int,
        definitions: [String: String]
    ) -> (ExportBlock, Int) {
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
                    || ListMarker(line: line) != nil
                    || isTableStart(lines, at: index) {
                    break
                }
            }

            // Leading indentation is layout, but trailing spaces are markdown's
            // hard-break syntax, so only the leading side is stripped.
            parts.append(String(line.drop { $0 == " " || $0 == "\t" }))
            index += 1
        }

        var source = ""
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

            source += text

            if offset < parts.count - 1 {
                source += hardBreak ? "\n" : " "
            }
        }

        // Inline formatting can span a Markdown hard break. Parse the complete
        // paragraph first so delimiters on different physical lines still
        // pair, then restore hard breaks inside the resulting nested spans.
        let content = restoringHardBreaks(
            in: MarkdownInlineParser.parse(source, definitions: definitions)
        )

        return (.paragraph(content), index)
    }

    private static func restoringHardBreaks(in spans: [ExportInline]) -> [ExportInline] {
        spans.flatMap { span -> [ExportInline] in
            switch span {
            case .text(let value):
                let parts = value.split(separator: "\n", omittingEmptySubsequences: false)
                var restored: [ExportInline] = []
                for (index, part) in parts.enumerated() {
                    if !part.isEmpty { restored.append(.text(String(part))) }
                    if index < parts.count - 1 { restored.append(.lineBreak) }
                }
                return restored
            case .emphasis(let children):
                return [.emphasis(restoringHardBreaks(in: children))]
            case .strong(let children):
                return [.strong(restoringHardBreaks(in: children))]
            case .strikethrough(let children):
                return [.strikethrough(restoringHardBreaks(in: children))]
            case .underline(let children):
                return [.underline(restoringHardBreaks(in: children))]
            case .link(let destination, let content):
                return [.link(
                    destination: destination,
                    content: restoringHardBreaks(in: content)
                )]
            case .code, .image, .lineBreak:
                return [span]
            }
        }
    }
}
