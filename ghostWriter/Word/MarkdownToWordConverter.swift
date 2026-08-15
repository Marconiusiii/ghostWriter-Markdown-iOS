import Foundation

nonisolated enum MarkdownToWordConverter {
    static func convert(title: String, markdown: String) throws -> Data {
        try WordprocessingMLWriter.write(
            title: title,
            document: document(from: markdown)
        )
    }

    static func document(from markdown: String) -> WordDocumentModel {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [WordBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("~~~") ? "~~~" : "```"
                var body: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
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
                    runs: inlineRuns(heading),
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
                        runs: inlineRuns(trimmed),
                        headingLevel: underline.first == "=" ? 1 : 2
                    )))
                    index += 2
                    continue
                }
            }

            if tableStarts(lines, at: index) {
                let (table, next) = parseTable(lines, at: index)
                blocks.append(.table(table))
                index = next
                continue
            }

            if let marker = ListMarker(line: line) {
                let level = max(0, LineAnalyzer.indentColumns(of: line) / 4)
                let listKind: WordListReference.Kind
                switch marker.style {
                case .unordered: listKind = .bullet
                case .ordered(let number): listKind = .numbered(start: number)
                }
                var content = marker.content
                if marker.taskBox != nil {
                    let completed = marker.taskBox?.lowercased() == "[x]"
                    content = (completed ? "Completed: " : "Not completed: ") + content
                }
                blocks.append(.paragraph(WordParagraph(
                    runs: inlineRuns(content),
                    list: WordListReference(
                        identifier: "markdown-list",
                        level: level,
                        kind: listKind
                    )
                )))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let text = trimmed.drop(while: { $0 == ">" || $0 == " " })
                blocks.append(.paragraph(WordParagraph(
                    runs: inlineRuns(String(text)),
                    isBlockQuote: true
                )))
                index += 1
                continue
            }

            if LineAnalyzer.isHorizontalRule(trimmed) {
                index += 1
                continue
            }

            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty
                    || LineAnalyzer.headingLevel(candidateTrimmed) != nil
                    || candidateTrimmed.hasPrefix(">")
                    || candidateTrimmed.hasPrefix("```")
                    || candidateTrimmed.hasPrefix("~~~")
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
            blocks.append(.paragraph(WordParagraph(runs: inlineRuns(joined))))
        }

        return WordDocumentModel(blocks: blocks)
    }

    static func inlineRuns(_ source: String) -> [WordRun] {
        parseInline(source, inherited: WordRun())
    }

    private static func parseInline(_ source: String, inherited: WordRun) -> [WordRun] {
        var runs: [WordRun] = []
        var remainder = source[...]
        while !remainder.isEmpty {
            if remainder.first == "\\", remainder.count > 1 {
                remainder.removeFirst()
                var literal = inherited
                literal.text = String(remainder.removeFirst())
                runs.append(literal)
                continue
            }
            if remainder.hasPrefix("!["),
               let closeLabel = remainder.firstIndex(of: "]"),
               remainder.index(after: closeLabel) < remainder.endIndex,
               remainder[remainder.index(after: closeLabel)] == "(",
               let closeDestination = remainder[remainder.index(closeLabel, offsetBy: 2)...].firstIndex(of: ")") {
                let alt = String(remainder[remainder.index(remainder.startIndex, offsetBy: 2)..<closeLabel])
                let destinationStart = remainder.index(closeLabel, offsetBy: 2)
                let destination = String(remainder[destinationStart..<closeDestination])
                var imageRun = inherited
                imageRun.text = alt.isEmpty ? "Image" : "Image: \(alt)"
                imageRun.hyperlink = destination
                runs.append(imageRun)
                remainder = remainder[remainder.index(after: closeDestination)...]
                continue
            }
            if remainder.hasPrefix("["),
               let closeLabel = remainder.firstIndex(of: "]"),
               remainder.index(after: closeLabel) < remainder.endIndex,
               remainder[remainder.index(after: closeLabel)] == "(",
               let closeDestination = remainder[remainder.index(closeLabel, offsetBy: 2)...].firstIndex(of: ")") {
                let labelStart = remainder.index(after: remainder.startIndex)
                let label = String(remainder[labelStart..<closeLabel])
                let destinationStart = remainder.index(closeLabel, offsetBy: 2)
                let destination = String(remainder[destinationStart..<closeDestination])
                var linked = parseInline(label, inherited: inherited)
                for index in linked.indices { linked[index].hyperlink = destination }
                runs += linked
                remainder = remainder[remainder.index(after: closeDestination)...]
                continue
            }

            if remainder.hasPrefix("***") || remainder.hasPrefix("___") {
                let delimiter = remainder.hasPrefix("***") ? "***" : "___"
                let afterOpen = remainder.dropFirst(3)
                if let close = afterOpen.range(of: delimiter) {
                    var formatting = inherited
                    formatting.bold = true
                    formatting.italic = true
                    runs += parseInline(String(afterOpen[..<close.lowerBound]), inherited: formatting)
                    remainder = afterOpen[close.upperBound...]
                    continue
                }
            }

            if remainder.hasPrefix("<u>"),
               let close = remainder.dropFirst(3).range(of: "</u>") {
                let afterOpen = remainder.dropFirst(3)
                var formatting = inherited
                formatting.underline = true
                runs += parseInline(String(afterOpen[..<close.lowerBound]), inherited: formatting)
                remainder = afterOpen[close.upperBound...]
                continue
            }

            let delimiters: [(String, WritableKeyPath<WordRun, Bool>)] = [
                ("**", \.bold), ("__", \.bold), ("~~", \.strikethrough),
                ("*", \.italic), ("_", \.italic), ("`", \.inlineCode)
            ]
            var matched = false
            for (delimiter, property) in delimiters where remainder.hasPrefix(delimiter) {
                let afterOpen = remainder.dropFirst(delimiter.count)
                if let close = afterOpen.range(of: delimiter) {
                    var formatting = inherited
                    formatting[keyPath: property] = true
                    runs += parseInline(String(afterOpen[..<close.lowerBound]), inherited: formatting)
                    remainder = afterOpen[close.upperBound...]
                    matched = true
                    break
                }
            }
            if matched { continue }

            let next = nextSpecialIndex(in: remainder) ?? remainder.endIndex
            var text: String
            if next == remainder.startIndex {
                text = String(remainder.removeFirst())
            } else {
                text = String(remainder[..<next])
                remainder = remainder[next...]
            }
            text = unescape(text)
            if !text.isEmpty {
                var run = inherited
                run.text = text
                runs.append(run)
            }
        }
        return merge(runs)
    }

    private static func nextSpecialIndex(in text: Substring) -> Substring.Index? {
        text.indices.first { index in
            "![]*_~`\\<".contains(text[index])
        }
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: #"\\([\\`*_{}\[\]()<>#+\-.!|~])"#, with: "$1", options: .regularExpression)
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
               previous.hyperlink == run.hyperlink {
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

    private static func parseTable(_ lines: [String], at start: Int) -> (WordTable, Int) {
        var rows = [WordTableRow(cells: splitRow(lines[start]).map(cellBlocks), isHeader: true)]
        var index = start + 2
        while index < lines.count {
            let line = lines[index]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, line.contains("|") else { break }
            rows.append(WordTableRow(cells: splitRow(line).map(cellBlocks)))
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

    private static func cellBlocks(_ text: String) -> [WordBlock] {
        [.paragraph(WordParagraph(runs: inlineRuns(text.replacingOccurrences(of: "<br>", with: "\n"))))]
    }
}
