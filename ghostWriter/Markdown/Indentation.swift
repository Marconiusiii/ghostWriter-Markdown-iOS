//
//  Indentation.swift
//  ghostWriter
//
//  Indent and outdent across whatever lines the selection touches. Like list
//  continuation this is pure text-in, text-out, so it behaves identically from
//  a toolbar button, a keyboard shortcut, or any assistive input.
//

import Foundation

/// A selection expressed as a character range, mirroring what the text view
/// reports but without depending on UIKit.
nonisolated struct TextSelection: Equatable, Sendable {
    var location: Int
    var length: Int

    var end: Int { location + length }
    var isEmpty: Bool { length == 0 }
}

struct IndentResult: Equatable {
    let text: String
    let selection: TextSelection
    /// Spoken confirmation, matching the web app's status announcements.
    let announcement: String
}

enum Indentation {
    /// Adds one indent level to every line the selection touches.
    static func indent(text: String, selection: TextSelection, unit: IndentUnit) -> IndentResult {
        transform(text: text, selection: selection, unit: unit, outdent: false)
    }

    /// Removes one indent level from every line the selection touches. Lines
    /// that are already flush left are left alone.
    static func outdent(text: String, selection: TextSelection, unit: IndentUnit) -> IndentResult {
        transform(text: text, selection: selection, unit: unit, outdent: true)
    }

    private static func transform(
        text: String,
        selection: TextSelection,
        unit: IndentUnit,
        outdent: Bool
    ) -> IndentResult {
        let characters = Array(text)
        let clampedLocation = min(max(selection.location, 0), characters.count)
        let clampedEnd = min(max(selection.end, clampedLocation), characters.count)

        let blockStart = ListContinuation.lineStartIndex(characters, before: clampedLocation)
        let blockEnd = ListContinuation.lineEndIndex(characters, from: clampedEnd)

        let block = String(characters[blockStart..<blockEnd])
        let lines = block.components(separatedBy: "\n")
        let unitText = unit.string

        var deltaForFirstLine = 0
        var totalDelta = 0
        var deepestLevel = 0

        let updatedLines: [String] = lines.enumerated().map { index, line in
            let updated: String
            if outdent {
                updated = removeOneLevel(from: line, unit: unit)
            } else {
                updated = unitText + line
            }

            let delta = updated.count - line.count
            if index == 0 { deltaForFirstLine = delta }
            totalDelta += delta

            deepestLevel = max(deepestLevel, level(of: updated, unit: unit))
            return updated
        }

        let updatedBlock = updatedLines.joined(separator: "\n")
        var updatedCharacters = characters
        updatedCharacters.replaceSubrange(blockStart..<blockEnd, with: Array(updatedBlock))

        // Keep the selection over the same text. The caret shifts by the change
        // applied to its own line; the far end shifts by the total change.
        let newLocation = max(blockStart, clampedLocation + deltaForFirstLine)
        let newLength = selection.isEmpty ? 0 : max(0, selection.length + totalDelta - deltaForFirstLine)

        let announcement: String
        if outdent {
            announcement = "Outdented to level \(deepestLevel)."
        } else {
            announcement = "Indented to level \(deepestLevel)."
        }

        return IndentResult(
            text: String(updatedCharacters),
            selection: TextSelection(location: newLocation, length: newLength),
            announcement: announcement
        )
    }

    /// Strips one indent level. Falls back to removing whatever leading
    /// whitespace exists when the line is not indented by an exact multiple of
    /// the unit, so mixed-indentation documents still outdent sensibly.
    static func removeOneLevel(from line: String, unit: IndentUnit) -> String {
        if line.hasPrefix(unit.string) {
            return String(line.dropFirst(unit.string.count))
        }

        // A tab counts as a full level regardless of the configured unit.
        if line.hasPrefix("\t") {
            return String(line.dropFirst())
        }

        // Otherwise remove up to the unit's width in spaces.
        var remaining = Substring(line)
        var removed = 0
        let maximum = max(1, unit.string.count)
        while removed < maximum, remaining.first == " " {
            remaining = remaining.dropFirst()
            removed += 1
        }
        return String(remaining)
    }

    /// The indent level of a line, in units.
    static func level(of line: String, unit: IndentUnit) -> Int {
        switch unit {
        case .tab:
            return line.prefix { $0 == "\t" }.count
        case .twoSpaces:
            return LineAnalyzer.indentColumns(of: line) / 2
        case .fourSpaces:
            return LineAnalyzer.indentColumns(of: line) / 4
        }
    }
}
