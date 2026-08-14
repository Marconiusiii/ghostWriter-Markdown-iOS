//
//  MarkdownTypingAnnouncement.swift
//  ghostWriter
//
//  Recognizes a completed Markdown structure immediately before the caret.
//  The caller supplies only the current line prefix, keeping this work bounded
//  and independent of the complete document while the writer types.
//

import Foundation

nonisolated struct MarkdownTypingAnnouncementCandidate: Equatable {
    let message: String
    let trailingBoundaryUTF16Length: Int
}

nonisolated enum MarkdownTypingAnnouncement {
    static func candidate(
        linePrefix: String,
        committedText: String
    ) -> MarkdownTypingAnnouncementCandidate? {
        if let message = message(
            linePrefix: linePrefix,
            insertedText: committedText
        ) {
            return MarkdownTypingAnnouncementCandidate(
                message: message,
                trailingBoundaryUTF16Length: 0
            )
        }

        guard let boundary = committedBoundary(in: committedText),
              let contentPrefix = removing(
                boundary,
                from: linePrefix
              ), let trigger = contentPrefix.last,
              let message = message(
                linePrefix: contentPrefix,
                insertedText: String(trigger)
              ) else { return nil }

        return MarkdownTypingAnnouncementCandidate(
            message: message,
            trailingBoundaryUTF16Length:
                linePrefix.utf16.count - contentPrefix.utf16.count
        )
    }

    static func message(
        linePrefix: String,
        insertedText: String
    ) -> String? {
        guard let trigger = insertedText.last else { return nil }

        switch trigger {
        case " ":
            return headingMessage(linePrefix)
        case "*":
            if linePrefix.firstMatch(
                of: /\*\*(?!\s)([^*]+?)\*\*$/
            ) != nil {
                return "Bold applied."
            }
            if linePrefix.firstMatch(
                of: /\*(?!\s)([^*]+?)\*$/
            ) != nil {
                return "Italics applied."
            }
        case "_":
            if linePrefix.firstMatch(
                of: /__(?!\s)([^_]+?)__$/
            ) != nil {
                return "Bold applied."
            }
            if closesUnderscoreItalics(linePrefix) {
                return "Italics applied."
            }
        case "~":
            if linePrefix.firstMatch(of: /~~([^~]+?)~~$/) != nil {
                return "Strikethrough applied."
            }
        case "`":
            if closesInlineCode(linePrefix) {
                return "Inline code applied."
            }
        case ")":
            if linePrefix.firstMatch(
                of: /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)$/
            ) != nil {
                return "Image created."
            }
            if linePrefix.firstMatch(
                of: /\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)$/
            ) != nil {
                return "Link created."
            }
        default:
            break
        }

        return nil
    }

    private static func headingMessage(_ linePrefix: String) -> String? {
        let trimmed = linePrefix.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.last == " " else { return nil }
        let marker = trimmed.dropLast()
        guard (1...6).contains(marker.count),
              marker.allSatisfy({ $0 == "#" }) else { return nil }
        return "Heading level \(marker.count)."
    }

    private enum CommittedBoundary {
        case space
        case tab
        case newLine
    }

    private static func committedBoundary(
        in committedText: String
    ) -> CommittedBoundary? {
        if committedText.hasSuffix("\r\n")
            || committedText.hasSuffix("\n")
            || committedText.hasSuffix("\r") {
            return .newLine
        }
        if committedText.hasSuffix(" ") { return .space }
        if committedText.hasSuffix("\t") { return .tab }
        return nil
    }

    private static func removing(
        _ boundary: CommittedBoundary,
        from linePrefix: String
    ) -> String? {
        switch boundary {
        case .space:
            guard linePrefix.hasSuffix(" ") else { return nil }
            return String(linePrefix.dropLast())
        case .tab:
            guard linePrefix.hasSuffix("\t") else { return nil }
            return String(linePrefix.dropLast())
        case .newLine:
            if linePrefix.hasSuffix("\r\n") {
                // Swift treats CRLF as one Character even though UIKit counts
                // it as two UTF-16 code units.
                return String(linePrefix.dropLast())
            }
            guard linePrefix.hasSuffix("\n")
                    || linePrefix.hasSuffix("\r") else { return nil }
            return String(linePrefix.dropLast())
        }
    }

    /// Mirrors MarkdownRenderer's word-boundary rule for underscore italics.
    private static func closesUnderscoreItalics(_ linePrefix: String) -> Bool {
        let characters = Array(linePrefix)
        guard characters.count >= 3,
              characters.last == "_",
              characters[characters.count - 2] != "_" else { return false }

        func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }

        var index = characters.count - 2
        while index > 0 {
            if characters[index] == "_" {
                let precededByWord = isWordCharacter(characters[index - 1])
                let followedBySpace = characters[index + 1].isWhitespace
                if !precededByWord, !followedBySpace,
                   index + 1 < characters.count - 1 {
                    return true
                }
            }
            index -= 1
        }

        if characters[0] == "_",
           !characters[1].isWhitespace,
           characters.count > 2 {
            return true
        }
        return false
    }

    private static func closesInlineCode(_ linePrefix: String) -> Bool {
        let trimmed = linePrefix.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("```"), !trimmed.hasPrefix("~~~") else {
            return false
        }
        return linePrefix.reduce(into: 0) { count, character in
            if character == "`" { count += 1 }
        } >= 2 && linePrefix.filter({ $0 == "`" }).count.isMultiple(of: 2)
    }
}
