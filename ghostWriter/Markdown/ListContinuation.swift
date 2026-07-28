//
//  ListContinuation.swift
//  ghostWriter
//
//  Automatic list behaviour when Return is pressed. This is a pure text
//  transformation: given the whole text and a cursor position, it returns the
//  new text and new cursor position. Keeping it free of any UIKit or keyboard
//  types is deliberate — it means the same logic applies no matter how the
//  return arrived, whether from the on-screen keyboard, a hardware keyboard,
//  braille screen input, or dictation.
//

import Foundation

/// The bullet or number that begins a list line.
struct ListMarker: Equatable {
    enum Style: Equatable {
        case unordered(Character)
        case ordered(Int)
    }

    let style: Style
    /// Leading whitespace exactly as written, so continuation preserves the
    /// user's choice of tabs or spaces rather than imposing our own.
    let indent: String
    /// Whitespace between the marker and the content.
    let spacing: String
    /// The text after the marker.
    let content: String
    /// An unchecked or checked task box, if this is a task list item.
    let taskBox: String?

    /// Parses a line into a marker, or returns nil if it is not a list item.
    init?(line: String) {
        var index = line.startIndex
        // Leading whitespace.
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        let indent = String(line[line.startIndex..<index])
        guard index < line.endIndex else { return nil }

        let style: Style
        let afterMarker: String.Index

        if "-*+".contains(line[index]) {
            style = .unordered(line[index])
            afterMarker = line.index(after: index)
        } else if line[index].isNumber {
            var digits = ""
            var cursor = index
            while cursor < line.endIndex, line[cursor].isNumber {
                digits.append(line[cursor])
                cursor = line.index(after: cursor)
            }
            // A number only starts a list when followed by "." or ")".
            guard cursor < line.endIndex, line[cursor] == "." || line[cursor] == ")",
                  let number = Int(digits) else { return nil }
            style = .ordered(number)
            afterMarker = line.index(after: cursor)
        } else {
            return nil
        }

        // At least one space must separate the marker from the content,
        // otherwise "1.5" would parse as a list item.
        var spacingEnd = afterMarker
        var spacing = ""
        while spacingEnd < line.endIndex, line[spacingEnd] == " " || line[spacingEnd] == "\t" {
            spacing.append(line[spacingEnd])
            spacingEnd = line.index(after: spacingEnd)
        }
        guard !spacing.isEmpty else { return nil }

        var remainder = String(line[spacingEnd...])

        // Task list boxes: "[ ] " or "[x] " immediately after the marker.
        var taskBox: String?
        if remainder.hasPrefix("[ ] ") || remainder.hasPrefix("[x] ") || remainder.hasPrefix("[X] ") {
            taskBox = String(remainder.prefix(3))
            remainder = String(remainder.dropFirst(4))
        }

        self.style = style
        self.indent = indent
        self.spacing = spacing
        self.content = remainder
        self.taskBox = taskBox
    }

    /// The marker text alone, without indent or content.
    var markerText: String {
        switch style {
        case .unordered(let character): return String(character)
        case .ordered(let number): return "\(number)."
        }
    }

    /// The prefix for the *next* item in this list — the same bullet, or the
    /// next number. A task box is carried over but always unchecked, since a
    /// new item should not inherit a completed state.
    var nextItemPrefix: String {
        let marker: String
        switch style {
        case .unordered(let character): marker = String(character)
        case .ordered(let number): marker = "\(number + 1)."
        }
        let box = taskBox != nil ? "[ ] " : ""
        return indent + marker + spacing + box
    }

    /// The full prefix of this line, used to measure where content begins.
    var currentPrefix: String {
        let box = taskBox.map { "\($0) " } ?? ""
        return indent + markerText + spacing + box
    }
}

/// The result of handling a return keypress.
struct EditResult: Equatable {
    let text: String
    let cursor: Int
}

enum ListContinuation {
    /// Handles Return at `cursor`. Returns nil when the line is not a list item,
    /// in which case the caller should let the text view insert a plain newline.
    ///
    /// Behaviour matches the web app: continuing a list inserts the next marker,
    /// and pressing Return on an item whose content is empty clears the marker
    /// and ends the list rather than adding another empty bullet.
    static func handleReturn(in text: String, cursor: Int) -> EditResult? {
        let characters = Array(text)
        let safeCursor = min(max(cursor, 0), characters.count)

        let lineStart = lineStartIndex(characters, before: safeCursor)
        let lineEnd = lineEndIndex(characters, from: safeCursor)
        let line = String(characters[lineStart..<lineEnd])

        guard let marker = ListMarker(line: line) else { return nil }

        // Empty item: remove the marker and end the list. The line becomes
        // blank rather than disappearing, which keeps the paragraph break the
        // user is about to type into.
        if marker.content.trimmingCharacters(in: .whitespaces).isEmpty {
            var updated = characters
            updated.replaceSubrange(lineStart..<lineEnd, with: [])
            return EditResult(text: String(updated), cursor: lineStart)
        }

        // Continue the list: insert a newline plus the next marker at the cursor.
        let prefix = "\n" + marker.nextItemPrefix
        var updated = characters
        updated.insert(contentsOf: Array(prefix), at: safeCursor)
        return EditResult(text: String(updated), cursor: safeCursor + prefix.count)
    }

    /// Renumbers consecutive ordered list items so that a list stays sequential
    /// after an insertion in the middle. Only runs over items at the same indent
    /// depth, so nested lists are numbered independently.
    static func renumberOrderedLists(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        // Tracks the next number to use at each indent depth.
        var counters: [Int: Int] = [:]
        var previousDepth: Int?

        for index in lines.indices {
            let line = lines[index]
            guard let marker = ListMarker(line: line),
                  case .ordered = marker.style else {
                // A blank line or non-list line ends the run of numbering.
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    counters.removeAll()
                    previousDepth = nil
                }
                continue
            }

            let depth = LineAnalyzer.indentColumns(of: line) / 2

            // Moving out to a shallower depth discards deeper counters so a new
            // nested list starts from its own first number.
            if let previous = previousDepth, depth < previous {
                for key in counters.keys where key > depth {
                    counters.removeValue(forKey: key)
                }
            }

            let number = counters[depth, default: 1]
            counters[depth] = number + 1
            previousDepth = depth

            let box = marker.taskBox.map { "\($0) " } ?? ""
            lines[index] = marker.indent + "\(number)." + marker.spacing + box + marker.content
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Line boundaries

    static func lineStartIndex(_ characters: [Character], before cursor: Int) -> Int {
        var index = cursor
        while index > 0, characters[index - 1] != "\n" {
            index -= 1
        }
        return index
    }

    static func lineEndIndex(_ characters: [Character], from cursor: Int) -> Int {
        var index = cursor
        while index < characters.count, characters[index] != "\n" {
            index += 1
        }
        return index
    }
}
