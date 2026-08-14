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
}
