//
//  PlainTextWriter.swift
//  ghostWriter
//
//  Flattens a document to readable prose.
//
//  The Plain Text share option used to hand over the markdown source verbatim,
//  which meant the recipient got hashes, asterisks, and bracket-link syntax —
//  a screen reader reads those aloud as punctuation, so the "plain" option was
//  the least readable of the four. This produces text that can actually be read
//  straight through: structure is conveyed by layout and by words, never by
//  markup that has to be decoded.
//

import Foundation

nonisolated enum PlainTextWriter {

    /// Wrapping width for underlines and table rules. Chosen to stay readable
    /// in a terminal or a mail body without forcing hard wraps on the text
    /// itself, which is left unwrapped so the reader's own software can reflow.
    private static let ruleWidth = 72

    static func write(title: String, markdown: String) -> String {
        let document = MarkdownDocumentParser.parse(markdown)
        var output: [String] = []

        // The document title is not part of the markdown body, so it is added
        // as a first heading. Without it a shared plain-text file arrives with
        // no indication of what it is.
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, !startsWithTopLevelHeading(document, matching: trimmedTitle) {
            output.append(trimmedTitle)
            output.append(String(repeating: "=", count: min(trimmedTitle.count, ruleWidth)))
            output.append("")
        }

        output += render(document.blocks, indent: "")

        return output
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Avoids repeating the title when the body already opens with it, which is
    /// the common case for documents named from their first heading.
    private static func startsWithTopLevelHeading(
        _ document: ExportDocument,
        matching title: String
    ) -> Bool {
        guard case .heading(_, let content)? = document.blocks.first else { return false }
        return content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(title) == .orderedSame
    }

    // MARK: - Blocks

    private static func render(_ blocks: [ExportBlock], indent: String) -> [String] {
        var output: [String] = []

        for block in blocks {
            switch block {
            case .heading(let level, let content):
                let text = inline(content)
                guard !text.isEmpty else { continue }
                output.append(indent + text)
                // Levels one and two get a rule underneath, the setext
                // convention. Deeper levels are prefixed instead, because six
                // distinct underline characters would be noise rather than
                // information.
                switch level {
                case 1:
                    output.append(indent + String(repeating: "=", count: min(text.count, ruleWidth)))
                case 2:
                    output.append(indent + String(repeating: "-", count: min(text.count, ruleWidth)))
                default:
                    output[output.count - 1] = indent + text + "  (heading level \(level))"
                }
                output.append("")

            case .paragraph(let content):
                let text = inline(content)
                guard !text.isEmpty else { continue }
                output += text.components(separatedBy: "\n").map { indent + $0 }
                output.append("")

            case .list(let list):
                output += renderList(list, indent: indent)
                output.append("")

            case .table(let table):
                output += renderTable(table, indent: indent)
                output.append("")

            case .blockQuote(let children):
                // Quoted text is marked with the email convention, which reads
                // naturally and survives copy and paste.
                let inner = render(children, indent: "")
                output += inner.map { line in
                    line.isEmpty ? indent + ">" : indent + "> " + line
                }
                output.append("")

            case .codeBlock(let language, let code):
                let label = language.map { "Code (\($0)):" } ?? "Code:"
                output.append(indent + label)
                output += code.components(separatedBy: "\n").map { indent + "    " + $0 }
                output.append("")

            case .thematicBreak:
                output.append(indent + String(repeating: "-", count: ruleWidth))
                output.append("")
            }
        }

        return output
    }

    private static func renderList(_ list: ExportList, indent: String) -> [String] {
        var output: [String] = []
        var number = list.start

        for item in list.items {
            let marker = list.isOrdered ? "\(number). " : "- "
            number += 1

            var text = inline(item.content)
            if let state = item.taskState {
                text = state.spokenPrefix + " " + text
            }

            let lines = text.components(separatedBy: "\n")
            // Continuation lines align under the first character of the item's
            // text rather than under its marker, so the list shape survives.
            let continuation = indent + String(repeating: " ", count: marker.count)
            for (offset, line) in lines.enumerated() {
                output.append(offset == 0 ? indent + marker + line : continuation + line)
            }

            if !item.children.isEmpty {
                let nested = render(item.children, indent: continuation)
                // Drop the trailing blank a nested block leaves behind, so
                // items do not drift apart as nesting deepens.
                output += nested.reversed().drop { $0.isEmpty }.reversed()
            }
        }

        return output
    }

    /// Tables are laid out as aligned columns with a header rule. Column widths
    /// come from the widest cell, so the grid holds together when read in a
    /// monospaced context, and each row still reads as a sensible line when it
    /// does not.
    private static func renderTable(_ table: ExportTable, indent: String) -> [String] {
        let columnCount = table.columnCount
        guard columnCount > 0 else { return [] }

        func cells(_ row: [[ExportInline]]) -> [String] {
            (0..<columnCount).map { column in
                column < row.count
                    ? inline(row[column]).replacingOccurrences(of: "\n", with: " ")
                    : ""
            }
        }

        let headerCells = cells(table.headers)
        let bodyRows = table.rows.map(cells)

        var widths = headerCells.map(\.count)
        for row in bodyRows {
            for (column, cell) in row.enumerated() {
                widths[column] = max(widths[column], cell.count)
            }
        }

        func line(_ cells: [String]) -> String {
            let padded = cells.enumerated().map { column, cell in
                cell.padding(toLength: max(cell.count, widths[column]), withPad: " ", startingAt: 0)
            }
            return indent + padded.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }

        var output: [String] = []
        if !headerCells.allSatisfy(\.isEmpty) {
            output.append(line(headerCells))
            output.append(indent + widths.map { String(repeating: "-", count: max($0, 1)) }
                .joined(separator: "  "))
        }
        output += bodyRows.map(line)
        return output
    }

    // MARK: - Inline

    /// Renders inline spans as prose. Emphasis carries no plain-text
    /// equivalent, so it is dropped rather than approximated with asterisks —
    /// the markup would be read aloud and the emphasis still would not be.
    static func inline(_ spans: [ExportInline]) -> String {
        var result = ""

        for span in spans {
            switch span {
            case .text(let value):
                result += value
            case .emphasis(let children),
                 .strong(let children),
                 .underline(let children):
                result += inline(children)
            case .strikethrough(let children):
                result += inline(children)
            case .code(let value):
                result += value
            case .link(let destination, let content):
                let label = inline(content)
                // A bare URL used as its own label would otherwise be printed
                // twice.
                result += label == destination ? label : "\(label) (\(destination))"
            case .image(let image):
                if let alt = image.alternativeText, !alt.isEmpty {
                    result += "[Image: \(alt)]"
                }
                // A decorative image contributes nothing to the reading, which
                // is exactly what empty alt text asks for.
            case .lineBreak:
                result += "\n"
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
