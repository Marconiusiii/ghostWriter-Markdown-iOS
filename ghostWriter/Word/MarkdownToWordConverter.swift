import Foundation

nonisolated enum MarkdownToWordConverter {
    static func convert(
        title: String,
        markdown: String,
        sourceDirectory: URL? = nil,
        documentLanguage: String = DocumentLanguage.resolvedTag(""),
        theme: WordExportTheme? = nil,
        usesSmartPunctuation: Bool = false,
        thematicSeparator: ThematicSeparator = .none
    ) throws -> Data {
        var document = document(from: markdown, title: title, thematicSeparator: thematicSeparator, usesOpeningPair: theme?.title != nil && theme?.subtitle != nil)
        document = applyingTheme(theme, to: document)
        if usesSmartPunctuation { document.blocks = try SmartPunctuation.wordBlocks(document.blocks) }
        return try WordprocessingMLWriter.write(
            title: title,
            document: document,
            sourceDirectory: sourceDirectory,
            documentLanguage: documentLanguage,
            theme: theme
        )
    }

    static func document(from markdown: String, title: String, thematicSeparator: ThematicSeparator = .none, usesOpeningPair: Bool = false) -> WordDocumentModel {
        var document = document(from: markdown, thematicSeparator: thematicSeparator)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOpeningPair = document.blocks.contains {
            if case .paragraph(let paragraph) = $0 { return paragraph.openingStyle == "title" }
            return false
        }
        if !cleanTitle.isEmpty, !startsWithMatchingTitle(document, title: cleanTitle), !(usesOpeningPair && hasOpeningPair) {
            document.blocks.insert(.paragraph(WordParagraph(
                runs: [WordRun(text: cleanTitle)],
                headingLevel: 1
            )), at: 0)
        }
        return document
    }

    static func document(from markdown: String, thematicSeparator: ThematicSeparator = .none) -> WordDocumentModel {
        document(from: markdown, thematicSeparator: thematicSeparator, checkCancellation: {})
    }

    static func document(from markdown: String, thematicSeparator: ThematicSeparator = .none, checkCancellation: () throws -> Void) rethrows -> WordDocumentModel {
        try checkCancellation()
        var lines = markdown.components(separatedBy: "\n")
        let definitions = try extractLinkDefinitions(&lines, checkCancellation: checkCancellation)
        var blocks: [WordBlock] = []
        var index = 0
        var nextListIdentifier = 1
        var activeLists: [ListSequenceKey: WordListReference] = [:]

        while index < lines.count {
            try checkCancellation()
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if ListMarker(line: line) == nil { activeLists.removeAll() }
            if trimmed.isEmpty {
                // A blank line in the Markdown becomes a real empty paragraph
                // in the Word document, so the spacing the writer typed is the
                // spacing they get. These used to be dropped, which is what
                // made exported documents read as one run-on block.
                blocks.append(.paragraph(WordParagraph(runs: [])))
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("~~~") ? "~~~" : "```"
                var body: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    try checkCancellation()
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.paragraph(WordParagraph(
                    runs: [WordRun(text: body.joined(separator: "\n"))],
                    isCodeBlock: true
                )))
                continue
            }

            if let level = LineAnalyzer.headingLevel(trimmed) {
                let heading = String(trimmed.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.paragraph(WordParagraph(
                    runs: inlineRuns(heading, definitions: definitions),
                    headingLevel: level
                )))
                index += 1
                continue
            }

            if index + 1 < lines.count {
                let underline = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if !underline.isEmpty,
                   underline.allSatisfy({ $0 == "=" || $0 == "-" }),
                   Set(underline).count == 1 {
                    blocks.append(.paragraph(WordParagraph(
                        runs: inlineRuns(trimmed, definitions: definitions),
                        headingLevel: underline.first == "=" ? 1 : 2
                    )))
                    index += 2
                    continue
                }
            }

            if tableStarts(lines, at: index) {
                let (table, next) = try parseTable(lines, at: index, definitions: definitions, checkCancellation: checkCancellation)
                blocks.append(.table(table))
                index = next
                continue
            }

            if LineAnalyzer.isHorizontalRule(trimmed) {
                blocks.append(.paragraph(WordParagraph(
                    runs: thematicSeparator.text.map { [WordRun(text: $0)] } ?? [], isThematicSeparator: true
                )))
                index += 1
                continue
            }

            if let marker = ListMarker(line: line) {
                let level = max(0, LineAnalyzer.indentColumns(of: line) / 4)
                let style: ListSequenceKey.Style
                let initialKind: WordListReference.Kind
                switch marker.style {
                case .unordered:
                    style = .bullet
                    initialKind = .bullet
                case .ordered(let number):
                    style = .numbered
                    initialKind = .numbered(start: number)
                }
                let sequenceKey = ListSequenceKey(level: level, style: style)
                let listReference: WordListReference
                if let existing = activeLists[sequenceKey] {
                    listReference = existing
                } else {
                    listReference = WordListReference(
                        identifier: "markdown-list-\(nextListIdentifier)",
                        level: level,
                        kind: initialKind
                    )
                    nextListIdentifier += 1
                    activeLists[sequenceKey] = listReference
                }
                var content = marker.content
                if marker.taskBox != nil {
                    let completed = marker.taskBox?.lowercased() == "[x]"
                    content = (completed ? "Completed: " : "Not completed: ") + content
                }
                blocks.append(.paragraph(WordParagraph(
                    runs: inlineRuns(content, definitions: definitions),
                    list: listReference
                )))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let text = trimmed.drop(while: { $0 == ">" || $0 == " " })
                blocks.append(.paragraph(WordParagraph(
                    runs: inlineRuns(String(text), definitions: definitions),
                    isBlockQuote: true
                )))
                index += 1
                continue
            }


            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                try checkCancellation()
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty
                    || LineAnalyzer.headingLevel(candidateTrimmed) != nil
                    || candidateTrimmed.hasPrefix(">")
                    || candidateTrimmed.hasPrefix("```")
                    || candidateTrimmed.hasPrefix("~~~")
                    || LineAnalyzer.isHorizontalRule(candidateTrimmed)
                    || ListMarker(line: candidate) != nil
                    || tableStarts(lines, at: index) {
                    break
                }
                paragraphLines.append(candidate)
                index += 1
            }
            let joined = paragraphLines.enumerated().map { offset, value in
                let hardBreak = value.hasSuffix("  ") || value.hasSuffix("\\")
                let clean = value.trimmingCharacters(in: .whitespaces)
                return clean + (hardBreak && offset < paragraphLines.count - 1 ? "\n" : " ")
            }.joined().trimmingCharacters(in: .whitespaces)
            blocks.append(.paragraph(WordParagraph(
                runs: inlineRuns(joined, definitions: definitions)
            )))
        }

        // A file ending in a newline yields one final empty line that the
        // writer did not type, so drop exactly one trailing empty paragraph.
        // Any blank lines beyond that were deliberate and are preserved.
        if markdown.hasSuffix("\n"),
           case .paragraph(let last) = blocks.last,
           last.runs.isEmpty,
           last.list == nil,
           last.headingLevel == nil {
            blocks.removeLast()
        }

        let content = markdown.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func heading(at index: Int) -> (level: Int, next: Int)? {
            guard index < content.count else { return nil }
            let line = content[index].trimmingCharacters(in: .whitespaces)
            if let level = LineAnalyzer.headingLevel(line) { return (level, index + 1) }
            if index + 1 < content.count {
                let underline = content[index + 1].trimmingCharacters(in: .whitespaces)
                if !underline.isEmpty, underline.allSatisfy({ $0 == "=" }) { return (1, index + 2) }
                if !underline.isEmpty, underline.allSatisfy({ $0 == "-" }) { return (2, index + 2) }
            }
            return nil
        }
        if let first = heading(at: 0), first.level == 1,
           let second = heading(at: first.next), second.level == 2 {
            let indices = blocks.indices.filter {
                if case .paragraph(let p) = blocks[$0] {
                    return p.headingLevel != nil || p.isThematicSeparator || p.isCodeBlock || p.isBlockQuote || p.list != nil || !p.runs.isEmpty
                }
                return true
            }
            if indices.count >= 2,
               case .paragraph(let firstBlock) = blocks[indices[0]], firstBlock.headingLevel == 1,
               case .paragraph(let secondBlock) = blocks[indices[1]], secondBlock.headingLevel == 2 {
                for (index, name) in zip(indices.prefix(2), ["title", "subtitle"]) {
                    if case .paragraph(var p) = blocks[index] { p.openingStyle = name; blocks[index] = .paragraph(p) }
                }
            }
        }
        return WordDocumentModel(blocks: blocks)
    }

    static func applyingTheme(_ theme: WordExportTheme?, to document: WordDocumentModel) -> WordDocumentModel {
        var result = document
        result.blocks = document.blocks.map { block in
            guard case .paragraph(var p) = block, p.isThematicSeparator,
                  let rule = theme?.thematicBreak else { return block }
            switch rule.behavior {
            case "separator": p.runs = [WordRun(text: rule.text ?? "")]
            case "pageBreak": p.runs = []; p.pageBreakBefore = true
            default: p.runs = []
            }
            return .paragraph(p)
        }
        return result
    }

    static func inlineRuns(
        _ source: String,
        definitions: [String: String] = [:]
    ) -> [WordRun] {
        wordRuns(from: MarkdownInlineParser.parse(source, definitions: definitions))
    }

    private static func wordRuns(
        from spans: [ExportInline],
        inherited: WordRun = WordRun()
    ) -> [WordRun] {
        var runs: [WordRun] = []
        for span in spans {
            switch span {
            case .text(let text):
                var run = inherited
                run.text = text
                runs.append(run)
            case .emphasis(let children):
                var formatting = inherited
                formatting.italic = true
                runs += wordRuns(from: children, inherited: formatting)
            case .strong(let children):
                var formatting = inherited
                formatting.bold = true
                runs += wordRuns(from: children, inherited: formatting)
            case .strikethrough(let children):
                var formatting = inherited
                formatting.strikethrough = true
                runs += wordRuns(from: children, inherited: formatting)
            case .underline(let children):
                var formatting = inherited
                formatting.underline = true
                runs += wordRuns(from: children, inherited: formatting)
            case .code(let text):
                var run = inherited
                run.text = text
                run.inlineCode = true
                runs.append(run)
            case .link(let destination, let children):
                var formatting = inherited
                formatting.hyperlink = destination
                runs += wordRuns(from: children, inherited: formatting)
            case .image(let image):
                var run = inherited
                run.image = WordImage(
                    fileName: image.source.removingPercentEncoding ?? image.source,
                    alternativeText: image.alternativeText,
                    isDecorative: image.isDecorative,
                    externalTarget: image.source
                )
                runs.append(run)
            case .lineBreak:
                var run = inherited
                run.text = "\n"
                runs.append(run)
            }
        }
        return merge(runs)
    }

    private static func merge(_ runs: [WordRun]) -> [WordRun] {
        var result: [WordRun] = []
        for run in runs {
            if var previous = result.last,
               previous.bold == run.bold,
               previous.italic == run.italic,
               previous.underline == run.underline,
               previous.strikethrough == run.strikethrough,
               previous.inlineCode == run.inlineCode,
               previous.hyperlink == run.hyperlink,
               previous.image == nil,
               run.image == nil {
                previous.text += run.text
                result[result.count - 1] = previous
            } else {
                result.append(run)
            }
        }
        return result
    }

    private static func tableStarts(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return lines[index].contains("|")
            && LineAnalyzer.isTableDivider(lines[index + 1].trimmingCharacters(in: .whitespaces))
    }

    private static func parseTable(
        _ lines: [String],
        at start: Int,
        definitions: [String: String],
        checkCancellation: () throws -> Void
    ) rethrows -> (WordTable, Int) {
        var rows = [WordTableRow(
            cells: splitRow(lines[start]).map { cellBlocks($0, definitions: definitions) },
            isHeader: true
        )]
        var index = start + 2
        while index < lines.count {
            try checkCancellation()
            let line = lines[index]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, line.contains("|") else { break }
            rows.append(WordTableRow(
                cells: splitRow(line).map { cellBlocks($0, definitions: definitions) }
            ))
            index += 1
        }
        return (WordTable(rows: rows), index)
    }

    private static func splitRow(_ line: String) -> [String] {
        var source = line.trimmingCharacters(in: .whitespaces)
        if source.hasPrefix("|") { source.removeFirst() }
        if source.hasSuffix("|") { source.removeLast() }
        return source.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func cellBlocks(
        _ text: String,
        definitions: [String: String]
    ) -> [WordBlock] {
        [.paragraph(WordParagraph(runs: inlineRuns(
            text.replacingOccurrences(of: "<br>", with: "\n"),
            definitions: definitions
        )))]
    }

    private static func startsWithMatchingTitle(
        _ document: WordDocumentModel,
        title: String
    ) -> Bool {
        guard case .paragraph(let first)? = document.blocks.first,
              first.headingLevel == 1 else { return false }
        return first.runs.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(title) == .orderedSame
    }

    private static func extractLinkDefinitions(_ lines: inout [String], checkCancellation: () throws -> Void) rethrows -> [String: String] {
        var definitions: [String: String] = [:]
        var remaining: [String] = []
        var insideCodeBlock = false

        for line in lines {
            try checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCodeBlock.toggle()
                remaining.append(line)
            } else if !insideCodeBlock,
                      let match = trimmed.firstMatch(
                        of: /^\[([^\]]+)\]:\s*(\S+)(?:\s+["'(].*["')])?$/
                      ) {
                definitions[String(match.1).lowercased()] = String(match.2)
            } else {
                remaining.append(line)
            }
        }
        lines = remaining
        return definitions
    }

    private struct ListSequenceKey: Hashable {
        enum Style: Hashable { case bullet, numbered }
        var level: Int
        var style: Style
    }
}
