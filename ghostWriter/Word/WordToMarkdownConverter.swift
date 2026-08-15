import Foundation

nonisolated enum WordToMarkdownConverter {
    private enum InlineStyle: Hashable {
        case underline
        case strikethrough
        case bold
        case italic

        var openingMarker: String {
            switch self {
            case .underline: "<u>"
            case .strikethrough: "~~"
            case .bold: "**"
            case .italic: "*"
            }
        }

        var closingMarker: String {
            switch self {
            case .underline: "</u>"
            default: openingMarker
            }
        }

        var tieBreakOrder: Int {
            switch self {
            case .underline: 0
            case .strikethrough: 1
            case .bold: 2
            case .italic: 3
            }
        }
    }

    private struct CharacterFragment {
        var character: Character
        var styles: Set<InlineStyle>
        var inlineCode: Bool
    }

    private struct MarkdownFragment {
        var text: String
        var styles: Set<InlineStyle>
        var inlineCode: Bool
    }

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
        let text = render(paragraph.runs)
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

    private static func render(_ runs: [WordRun]) -> String {
        var result = ""
        var index = 0
        while index < runs.count {
            if runs[index].hyperlink == nil, isFootnoteReference(runs[index].text) {
                result += runs[index].text
                index += 1
                continue
            }
            let hyperlink = runs[index].hyperlink
            var end = index + 1
            while end < runs.count,
                  runs[end].hyperlink == hyperlink,
                  !isFootnoteReference(runs[end].text) {
                end += 1
            }
            let group = Array(runs[index..<end])
            let label = renderFormatting(group)
            if let hyperlink, !hyperlink.isEmpty {
                result += "[\(label)](\(escapeDestination(hyperlink)))"
            } else {
                result += label
            }
            index = end
        }
        return result
    }

    private static func isFootnoteReference(_ text: String) -> Bool {
        text.hasPrefix("[^") && text.hasSuffix("]")
    }

    private static func renderFormatting(_ runs: [WordRun]) -> String {
        let fragments = normalizedFragments(runs)
        var result = ""
        var activeStyles: [InlineStyle] = []

        for (index, fragment) in fragments.enumerated() {
            if fragment.inlineCode {
                closeStyles(&activeStyles, into: &result)
                result += "`\(fragment.text.replacingOccurrences(of: "`", with: "\\`"))`"
                continue
            }

            var retainedCount = 0
            while retainedCount < activeStyles.count,
                  fragment.styles.contains(activeStyles[retainedCount]) {
                retainedCount += 1
            }
            if retainedCount < activeStyles.count {
                for style in activeStyles[retainedCount...].reversed() {
                    result += style.closingMarker
                }
                activeStyles.removeSubrange(retainedCount...)
            }

            let retained = Set(activeStyles)
            let additions = fragment.styles
                .subtracting(retained)
                .sorted { left, right in
                    let leftEnd = styleEnd(left, from: index, fragments: fragments)
                    let rightEnd = styleEnd(right, from: index, fragments: fragments)
                    if leftEnd != rightEnd { return leftEnd > rightEnd }
                    return left.tieBreakOrder < right.tieBreakOrder
                }
            for style in additions {
                result += style.openingMarker
                activeStyles.append(style)
            }
            result += escape(fragment.text)
        }

        closeStyles(&activeStyles, into: &result)
        return result
    }

    private static func normalizedFragments(_ runs: [WordRun]) -> [MarkdownFragment] {
        var characters: [CharacterFragment] = []
        for run in runs {
            var styles: Set<InlineStyle> = []
            if !run.inlineCode {
                if run.underline { styles.insert(.underline) }
                if run.strikethrough { styles.insert(.strikethrough) }
                if run.bold { styles.insert(.bold) }
                if run.italic { styles.insert(.italic) }
            }
            characters += run.text.map {
                CharacterFragment(character: $0, styles: styles, inlineCode: run.inlineCode)
            }
        }

        for style in [InlineStyle.underline, .strikethrough, .bold, .italic] {
            var index = 0
            while index < characters.count {
                guard characters[index].styles.contains(style) else {
                    index += 1
                    continue
                }
                let start = index
                while index < characters.count, characters[index].styles.contains(style) {
                    index += 1
                }
                let end = index
                var leading = start
                while leading < end, characters[leading].character.isWhitespace {
                    characters[leading].styles.remove(style)
                    leading += 1
                }
                var trailing = end
                while trailing > leading, characters[trailing - 1].character.isWhitespace {
                    characters[trailing - 1].styles.remove(style)
                    trailing -= 1
                }
            }
        }

        var result: [MarkdownFragment] = []
        for character in characters {
            if var last = result.last,
               last.styles == character.styles,
               last.inlineCode == character.inlineCode {
                last.text.append(character.character)
                result[result.count - 1] = last
            } else {
                result.append(MarkdownFragment(
                    text: String(character.character),
                    styles: character.styles,
                    inlineCode: character.inlineCode
                ))
            }
        }
        return result
    }

    private static func styleEnd(
        _ style: InlineStyle,
        from start: Int,
        fragments: [MarkdownFragment]
    ) -> Int {
        var index = start
        while index + 1 < fragments.count,
              !fragments[index + 1].inlineCode,
              fragments[index + 1].styles.contains(style) {
            index += 1
        }
        return index
    }

    private static func closeStyles(_ styles: inout [InlineStyle], into result: inout String) {
        for style in styles.reversed() {
            result += style.closingMarker
        }
        styles.removeAll(keepingCapacity: true)
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
