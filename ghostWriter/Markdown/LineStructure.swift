//
//  LineStructure.swift
//  ghostWriter
//
//  Works out what a single line of markdown *is* — a heading, a list item, a
//  table row and so on. This drives the spoken description of the cursor's
//  current line, which is how a writer knows where they are in the document
//  without being able to see its shape.
//

import Foundation

nonisolated enum LineKind: Equatable, Sendable {
    case blank
    case heading(level: Int)
    case unorderedItem(depth: Int)
    case orderedItem(number: Int, depth: Int)
    case blockquote(depth: Int)
    case codeFence
    case codeContent
    case tableRow
    case tableDivider
    case horizontalRule
    case paragraph
}

nonisolated struct LineStructure: Sendable {
    let kind: LineKind
    /// Indentation measured in columns, with tabs counted as two, matching the
    /// web app's `countIndent`.
    let indentColumns: Int

    /// Spoken form used as the editor's accessibility value. Phrased as short
    /// noun phrases because this is heard constantly while moving the cursor,
    /// and long sentences become noise.
    var spokenDescription: String {
        switch kind {
        case .blank:
            return "Blank line"
        case .heading(let level):
            return "Heading level \(level)"
        case .unorderedItem(let depth):
            return depth > 0 ? "Bullet, level \(depth + 1)" : "Bullet"
        case .orderedItem(let number, let depth):
            return depth > 0 ? "Item \(number), level \(depth + 1)" : "Item \(number)"
        case .blockquote(let depth):
            return depth > 1 ? "Quote, level \(depth)" : "Quote"
        case .codeFence:
            return "Code fence"
        case .codeContent:
            return "Code"
        case .tableRow:
            return "Table row"
        case .tableDivider:
            return "Table divider"
        case .horizontalRule:
            return "Horizontal rule"
        case .paragraph:
            return "Paragraph"
        }
    }
}

nonisolated enum LineAnalyzer {
    /// Counts leading whitespace in columns. A tab counts as two columns, which
    /// keeps tab-indented and space-indented documents comparable.
    static func indentColumns(of line: String) -> Int {
        var columns = 0
        for character in line {
            if character == "\t" {
                columns += 2
            } else if character == " " {
                columns += 1
            } else {
                break
            }
        }
        return columns
    }

    /// Analyses one line. `insideCodeBlock` is supplied by the caller because a
    /// line cannot tell on its own whether it sits inside a fenced block — that
    /// depends on how many fences appeared above it.
    static func analyze(_ line: String, insideCodeBlock: Bool = false) -> LineStructure {
        let indent = indentColumns(of: line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            return LineStructure(kind: .codeFence, indentColumns: indent)
        }

        // Inside a fence everything is literal, so no further parsing applies.
        if insideCodeBlock {
            return LineStructure(kind: .codeContent, indentColumns: indent)
        }

        if trimmed.isEmpty {
            return LineStructure(kind: .blank, indentColumns: indent)
        }

        if let level = headingLevel(trimmed) {
            return LineStructure(kind: .heading(level: level), indentColumns: indent)
        }

        if isHorizontalRule(trimmed) {
            return LineStructure(kind: .horizontalRule, indentColumns: indent)
        }

        if trimmed.hasPrefix(">") {
            return LineStructure(kind: .blockquote(depth: blockquoteDepth(trimmed)), indentColumns: indent)
        }

        if let marker = ListMarker(line: line) {
            let depth = indent / 2
            switch marker.style {
            case .unordered:
                return LineStructure(kind: .unorderedItem(depth: depth), indentColumns: indent)
            case .ordered(let number):
                return LineStructure(kind: .orderedItem(number: number, depth: depth), indentColumns: indent)
            }
        }

        if isTableDivider(trimmed) {
            return LineStructure(kind: .tableDivider, indentColumns: indent)
        }

        if trimmed.contains("|") {
            return LineStructure(kind: .tableRow, indentColumns: indent)
        }

        return LineStructure(kind: .paragraph, indentColumns: indent)
    }

    /// One to six leading hashes followed by a space. The trailing space is
    /// required so that a line of "###" alone is not treated as a heading.
    static func headingLevel(_ trimmed: String) -> Int? {
        var hashes = 0
        for character in trimmed {
            if character == "#" {
                hashes += 1
                if hashes > 6 { return nil }
            } else {
                break
            }
        }
        guard hashes > 0 else { return nil }

        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return hashes
    }

    static func blockquoteDepth(_ trimmed: String) -> Int {
        var depth = 0
        var remaining = Substring(trimmed)
        while remaining.first == ">" {
            depth += 1
            remaining = remaining.dropFirst()
            if remaining.first == " " { remaining = remaining.dropFirst() }
        }
        return depth
    }

    /// Three or more of the same marker, optionally separated by spaces.
    static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, "-*_".contains(first) else { return false }
        let stripped = trimmed.filter { !$0.isWhitespace }
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    /// A row of cells consisting only of dashes and optional alignment colons.
    static func isTableDivider(_ trimmed: String) -> Bool {
        guard trimmed.contains("|") || trimmed.contains("-") else { return false }
        let cells = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
        guard !cells.isEmpty else { return false }

        return cells.allSatisfy { cell in
            let candidate = cell.trimmingCharacters(in: .whitespaces)
            guard candidate.count >= 3 else { return false }
            let core = candidate
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    /// Scans from the start of the text to decide whether `lineIndex` falls
    /// inside a fenced code block, by counting fences above it.
    static func isInsideCodeBlock(lines: [String], lineIndex: Int) -> Bool {
        var inside = false
        for index in 0..<min(lineIndex, lines.count) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inside.toggle()
            }
        }
        return inside
    }
}
