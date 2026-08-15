import Foundation

nonisolated enum WordToMarkdownConverter {
    static func convert(data: Data) throws -> String {
        markdown(from: try WordprocessingMLReader.read(data: data))
    }

    static func markdown(from document: WordDocumentModel) -> String {
        var sections = render(blocks: document.blocks)
        if !document.footnotes.isEmpty {
            let notes = document.footnotes.keys.sorted(by: noteOrder).compactMap { key -> String? in
                guard let blocks = document.footnotes[key] else { return nil }
                let body = render(blocks: blocks)
                    .joined(separator: "\n")
                    .replacingOccurrences(of: "\n", with: "\n    ")
                return "[^\(key)]: \(body)"
            }
            sections += ["", notes.joined(separator: "\n")]
        }
        return sections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func render(blocks: [WordBlock]) -> [String] {
        var result: [String] = []
        var previousWasList = false
        var listCounters: [String: Int] = [:]
        var previousList: WordListReference?
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                let numberedValue: Int?
                if let list = paragraph.list,
                   case .numbered(let start) = list.kind {
                    if let previousList, previousList.identifier != list.identifier {
                        listCounters.removeAll()
                    } else if let previousList, list.level <= previousList.level {
                        let prefix = "\(list.identifier):"
                        listCounters.keys
                            .filter { key in
                                guard key.hasPrefix(prefix),
                                      let level = Int(key.dropFirst(prefix.count)) else { return false }
                                return level > list.level
                            }
                            .forEach { listCounters[$0] = nil }
                    }
                    let key = "\(list.identifier):\(list.level)"
                    let value = listCounters[key] ?? start
                    listCounters[key] = value + 1
                    numberedValue = value
                } else {
                    numberedValue = nil
                }
                let rendered = render(
                    paragraph: paragraph,
                    numberedValue: numberedValue
                )
                guard !rendered.isEmpty else {
                    if result.last != "" { result.append("") }
                    previousWasList = false
                    listCounters.removeAll()
                    continue
                }
                if paragraph.list == nil, !result.isEmpty, result.last != "" {
                    result.append("")
                } else if paragraph.list != nil, !previousWasList, !result.isEmpty, result.last != "" {
                    result.append("")
                }
                result.append(rendered)
                previousWasList = paragraph.list != nil
                previousList = paragraph.list
                if paragraph.list == nil {
                    listCounters.removeAll()
                    previousList = nil
                }
            case .table(let table):
                if !result.isEmpty, result.last != "" { result.append("") }
                result += render(table: table)
                result.append("")
                previousWasList = false
                listCounters.removeAll()
                previousList = nil
            }
        }
        while result.last == "" { result.removeLast() }
        return result
    }

    private static func render(
        paragraph: WordParagraph,
        numberedValue: Int?
    ) -> String {
        let text = paragraph.runs.map(render).joined()
        if let level = paragraph.headingLevel {
            return String(repeating: "#", count: level) + " " + text
        }
        if let list = paragraph.list {
            let indent = String(repeating: "    ", count: max(0, list.level))
            let marker: String
            switch list.kind {
            case .bullet: marker = "- "
            case .numbered(let start): marker = "\(numberedValue ?? start). "
            }
            return indent + marker + text
        }
        if paragraph.isBlockQuote {
            return text.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
        }
        if paragraph.isCodeBlock {
            let unformatted = paragraph.runs.map(\.text).joined()
            return "```\n\(unformatted)\n```"
        }
        return escapeParagraphStart(
            text.replacingOccurrences(of: "\n", with: "  \n")
        )
    }

    private static func render(_ run: WordRun) -> String {
        if run.text.hasPrefix("[^") && run.text.hasSuffix("]") {
            return run.text
        }
        var text = escape(run.text)
        if run.inlineCode {
            text = "`\(run.text.replacingOccurrences(of: "`", with: "\\`"))`"
        } else {
            if run.bold { text = "**\(text)**" }
            if run.italic { text = "*\(text)*" }
            if run.strikethrough { text = "~~\(text)~~" }
        }
        if let hyperlink = run.hyperlink, !hyperlink.isEmpty {
            text = "[\(text)](\(escapeDestination(hyperlink)))"
        }
        return text
    }

    private static func render(table: WordTable) -> [String] {
        guard !table.rows.isEmpty else { return [] }
        let columnCount = table.rows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else { return [] }

        let hasHeader = table.rows.first?.isHeader == true
        let header = hasHeader
            ? cells(from: table.rows[0], count: columnCount)
            : Array(repeating: "", count: columnCount)
        let bodyStart = hasHeader ? 1 : 0
        var lines = [row(header), row(Array(repeating: "---", count: columnCount))]
        for tableRow in table.rows.dropFirst(bodyStart) {
            lines.append(row(cells(from: tableRow, count: columnCount)))
        }
        return lines
    }

    private static func cells(from row: WordTableRow, count: Int) -> [String] {
        (0..<count).map { index in
            guard index < row.cells.count else { return "" }
            return render(blocks: row.cells[index])
                .joined(separator: " ")
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    private static func row(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_{}[]<>#~|".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    private static func escapeDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: ")", with: "%29")
    }

    private static func escapeParagraphStart(_ text: String) -> String {
        if text.hasPrefix("- ") || text.hasPrefix("+ ") {
            return "\\" + text
        }
        if text.first?.isNumber == true,
           let match = text.firstMatch(of: /^(\d+)([.)])\s/) {
            let marker = String(match.1) + "\\" + String(match.2) + " "
            return marker + text.dropFirst(match.0.count)
        }
        return text
    }

    private static func noteOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = Int(lhs.replacingOccurrences(of: "endnote-", with: "")) ?? .max
        let right = Int(rhs.replacingOccurrences(of: "endnote-", with: "")) ?? .max
        return left == right ? lhs < rhs : left < right
    }
}
