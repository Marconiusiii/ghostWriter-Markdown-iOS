import Foundation

/// Normalized Markdown with source-local references already resolved and staged.
nonisolated enum CompilationMarkdownWriter {
    static func write(_ document: ExportDocument) -> String {
        var headingCounter = 0
        if document.compilationSections.isEmpty { return blocks(document.blocks, headingCounter: &headingCounter) + "\n" }
        return document.compilationSections.enumerated().map { index, section in
            "<a id=\"document-\(index + 1)\"></a>\n\n" + blocks(Array(document.blocks[section.start..<section.end]), headingCounter: &headingCounter)
        }.joined(separator: "\n\n") + "\n"
    }
    static func escape(_ text: String) -> String {
        text.reduce(into: "") { output, char in
            if "\\`*_{}[]<>#+-.!|~".contains(char) { output.append("\\") }
            output.append(char)
        }
    }
    static func inline(_ values: [ExportInline]) -> String {
        values.map { value in
            switch value {
            case .text(let text): return escape(text)
            case .emphasis(let c): return "*" + inline(c) + "*"
            case .strong(let c): return "**" + inline(c) + "**"
            case .strikethrough(let c): return "~~" + inline(c) + "~~"
            case .underline(let c): return "<u>" + inline(c) + "</u>"
            case .code(let text):
                let fence = String(repeating: "`", count: max(1, text.split(whereSeparator: { $0 != "`" }).map(\.count).max().map { $0 + 1 } ?? 1))
                return fence + " " + text + " " + fence
            case .link(let destination, let c): return "[" + inline(c) + "](<" + destination.replacingOccurrences(of: " ", with: "%20") + ">)"
            case .image(let image):
                let title = image.title.map { " \"" + $0.replacingOccurrences(of: "\"", with: "\\\"") + "\"" } ?? ""
                return "![" + escape(image.alternativeText ?? "") + "](<" + image.source.replacingOccurrences(of: " ", with: "%20") + ">" + title + ")"
            case .lineBreak: return "  \n"
            }
        }.joined()
    }
    static func blocks(_ values: [ExportBlock], headingCounter: inout Int) -> String {
        values.map { value in
            switch value {
            case .heading(let level, let c):
                headingCounter += 1
                return "<a id=\"heading-\(headingCounter)\"></a>\n\n" + String(repeating: "#", count: level) + " " + inline(c)
            case .paragraph(let c): return inline(c)
            case .blockQuote(let c): return blocks(c, headingCounter: &headingCounter).components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            case .codeBlock(let language, let code):
                let count = max(3, (code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0) + 1)
                let fence = String(repeating: "`", count: count)
                return fence + (language ?? "") + "\n" + code + "\n" + fence
            case .thematicBreak: return "---"
            case .list(let list):
                return list.items.enumerated().map { index, item in
                    let marker = list.isOrdered ? "\(list.start + index). " : "- "
                    let task = item.taskState.map { $0 == .completed ? "[x] " : "[ ] " } ?? ""
                    let children = item.children.isEmpty ? "" : "\n" + blocks(item.children, headingCounter: &headingCounter).components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
                    return marker + task + inline(item.content) + children
                }.joined(separator: "\n")
            case .table(let table):
                func row(_ cells: [[ExportInline]]) -> String { "| " + cells.map(inline).joined(separator: " | ") + " |" }
                let rule = (0..<table.columnCount).map { column -> String in
                    switch table.alignment(forColumn: column) {
                    case .center: ":---:"
                    case .trailing: "---:"
                    case .leading: ":---"
                    case .natural: "---"
                    }
                }
                return ([row(table.headers), "| " + rule.joined(separator: " | ") + " |"] + table.rows.map(row)).joined(separator: "\n")
            }
        }.joined(separator: "\n\n")
    }
}
