//
//  OutlineBuilder.swift
//  ghostWriter
//
//  Extracts the heading structure of a document so it can be navigated as a
//  list. A plain text field is a single flat element to VoiceOver, with no
//  internal structure to move through — this gives that structure back.
//

import Foundation

struct OutlineEntry: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let level: Int
    /// Character offset of the start of the heading's text, used to place the
    /// cursor when the user selects this entry.
    let characterOffset: Int
    /// Zero-based line number, shown as context.
    let lineNumber: Int

    /// Spoken as a heading at the right level, so VoiceOver's heading rotor
    /// works inside the outline itself.
    var spokenLabel: String {
        title.isEmpty ? "Empty heading, level \(level)" : title
    }
}

enum HeadingNavigationDirection {
    case next
    case previous
}

enum OutlineBuilder {
    /// Walks the text line by line, collecting headings. Lines inside fenced
    /// code blocks are skipped, since a "#" there is literal text rather than a
    /// heading.
    static func build(from text: String) -> [OutlineEntry] {
        var entries: [OutlineEntry] = []
        var offset = 0
        var insideCodeBlock = false

        for (lineNumber, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCodeBlock.toggle()
                offset += line.count + 1
                continue
            }

            if !insideCodeBlock, let level = LineAnalyzer.headingLevel(trimmed) {
                let title = String(trimmed.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                    // Closing hashes are optional in markdown and are not part
                    // of the title.
                    .replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)

                entries.append(
                    OutlineEntry(
                        title: title,
                        level: level,
                        characterOffset: offset,
                        lineNumber: lineNumber
                    )
                )
            }

            // +1 for the newline that `components(separatedBy:)` removed.
            offset += line.count + 1
        }

        return entries
    }

    /// Finds the heading reached by moving from the insertion point. A heading
    /// beginning exactly at the insertion point is the current destination, so
    /// navigation advances past it in either direction.
    static func destination(
        in entries: [OutlineEntry],
        from characterOffset: Int,
        moving direction: HeadingNavigationDirection
    ) -> OutlineEntry? {
        switch direction {
        case .next:
            return entries.first { $0.characterOffset > characterOffset }
        case .previous:
            return entries.last { $0.characterOffset < characterOffset }
        }
    }
}
