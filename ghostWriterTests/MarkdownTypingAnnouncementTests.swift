//
//  MarkdownTypingAnnouncementTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct MarkdownTypingAnnouncementTests {
    @Test func recognizesCompletedHeadings() {
        for level in 1...6 {
            let marker = String(repeating: "#", count: level) + " "
            #expect(
                MarkdownTypingAnnouncement.message(
                    linePrefix: marker,
                    insertedText: " "
                ) == "Heading level \(level)."
            )
        }
        #expect(message("## ", inserted: "## ") == "Heading level 2.")
    }

    @Test func rejectsIncompleteOrInvalidHeadings() {
        #expect(message("##", inserted: "#") == nil)
        #expect(message("####### ", inserted: " ") == nil)
        #expect(message("Text ## ", inserted: " ") == nil)
    }

    @Test func recognizesFormattingOnlyWhenItCloses() {
        #expect(message("**bold", inserted: "d") == nil)
        #expect(message("**bold**", inserted: "*") == "Bold applied.")
        #expect(message("__bold__", inserted: "_") == "Bold applied.")
        #expect(message("*italic*", inserted: "*") == "Italics applied.")
        #expect(message("_italic_", inserted: "_") == "Italics applied.")
        #expect(message("~~removed~~", inserted: "~") == "Strikethrough applied.")
        #expect(message("`value`", inserted: "`") == "Inline code applied.")
        #expect(message("**bold**", inserted: "**bold**") == "Bold applied.")
    }

    @Test func recognizesCompletedLinksAndImages() {
        #expect(
            message("[Home](https://example.com)", inserted: ")")
                == "Link created."
        )
        #expect(
            message("![Logo](https://example.com/logo.png)", inserted: ")")
                == "Image created."
        )
    }

    @Test func recognizesBSIFormattingBeforeSpaceOrReturn() {
        #expect(candidate("**bold** ", committed: "**bold** ")?.message == "Bold applied.")
        #expect(candidate("**bold**\n", committed: "**bold**\n")?.message == "Bold applied.")
        #expect(candidate("_italics_ ", committed: "_italics_ ")?.message == "Italics applied.")
        #expect(candidate("~~removed~~\n", committed: "\n")?.message == "Strikethrough applied.")
        #expect(candidate("`code`\r\n", committed: "\r\n")?.message == "Inline code applied.")
        #expect(candidate("[Home](https://example.com)\n", committed: "\n")?.message == "Link created.")
        #expect(candidate("![Logo](image.png) ", committed: " ")?.message == "Image created.")
        #expect(candidate("**bold**\t", committed: "\t")?.message == "Bold applied.")
    }

    @Test func consumesOnlyTheCurrentCommitBoundary() {
        #expect(candidate("**bold**  ", committed: " ") == nil)
        #expect(candidate("**bold**\n\n", committed: "\n") == nil)
        #expect(candidate("## ", committed: "## ")?.message == "Heading level 2.")
        #expect(
            candidate("**bold** ", committed: " ")?
                .trailingBoundaryUTF16Length == 1
        )
        #expect(
            candidate("**bold**\r\n", committed: "\r\n")?
                .trailingBoundaryUTF16Length == 2
        )
    }

    @Test func rejectsMalformedLinksAndImages() {
        #expect(message("[](https://example.com)", inserted: ")") == nil)
        #expect(message("[Home]()", inserted: ")") == nil)
        #expect(message("[Home](two words)", inserted: ")") == nil)
        #expect(message("![Logo]()", inserted: ")") == nil)
    }

    @Test func rejectsCodeFencesAsInlineCode() {
        #expect(message("```", inserted: "`") == nil)
        #expect(message("```swift", inserted: "t") == nil)
    }

    private func message(
        _ linePrefix: String,
        inserted: String
    ) -> String? {
        MarkdownTypingAnnouncement.message(
            linePrefix: linePrefix,
            insertedText: inserted
        )
    }

    private func candidate(
        _ linePrefix: String,
        committed: String
    ) -> MarkdownTypingAnnouncementCandidate? {
        MarkdownTypingAnnouncement.candidate(
            linePrefix: linePrefix,
            committedText: committed
        )
    }
}
