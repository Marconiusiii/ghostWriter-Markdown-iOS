//
//  TitleDerivationTests.swift
//  ghostWriterTests
//
//  The document name is taken from the first line of the text, so markdown
//  syntax has to be stripped out of it. A bug here produced a file literally
//  named "#".
//

import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct TitleDerivationTests {

    @Test func stripsHeadingHashes() {
        #expect(EditorView.stripMarkdownSyntax("# My Title") == "My Title")
        #expect(EditorView.stripMarkdownSyntax("### Deeper") == "Deeper")
    }

    /// A heading being typed is still a heading. This is the case that produced
    /// a filename of "#".
    @Test func stripsPartiallyTypedHeading() {
        #expect(EditorView.stripMarkdownSyntax("#") == "")
        #expect(EditorView.stripMarkdownSyntax("# ") == "")
        #expect(EditorView.stripMarkdownSyntax("#M") == "M")
    }

    @Test func stripsClosingHashes() {
        #expect(EditorView.stripMarkdownSyntax("## Centered ##") == "Centered")
    }

    @Test func stripsListMarkers() {
        #expect(EditorView.stripMarkdownSyntax("- A bullet") == "A bullet")
        #expect(EditorView.stripMarkdownSyntax("* A bullet") == "A bullet")
        #expect(EditorView.stripMarkdownSyntax("1. First") == "First")
        #expect(EditorView.stripMarkdownSyntax("2) Second") == "Second")
    }

    @Test func stripsTaskBoxes() {
        #expect(EditorView.stripMarkdownSyntax("- [ ] Buy milk") == "Buy milk")
        #expect(EditorView.stripMarkdownSyntax("- [x] Done thing") == "Done thing")
    }

    @Test func stripsBlockquotes() {
        #expect(EditorView.stripMarkdownSyntax("> Quoted") == "Quoted")
        #expect(EditorView.stripMarkdownSyntax(">> Deeply quoted") == "Deeply quoted")
    }

    @Test func stripsInlineEmphasis() {
        #expect(EditorView.stripMarkdownSyntax("# **Bold** title") == "Bold title")
        #expect(EditorView.stripMarkdownSyntax("*Italic*") == "Italic")
        #expect(EditorView.stripMarkdownSyntax("~~Struck~~") == "Struck")
        #expect(EditorView.stripMarkdownSyntax("`code`") == "code")
    }

    /// A link should contribute its visible text, not its URL — a filename
    /// containing "https" would be useless.
    @Test func keepsLinkTextAndDropsTarget() {
        #expect(
            EditorView.stripMarkdownSyntax("[Marconius](https://marconius.com)") == "Marconius"
        )
        #expect(
            EditorView.stripMarkdownSyntax("![A ghost](ghost.png)") == "A ghost"
        )
    }

    @Test func leavesPlainTextAlone() {
        #expect(EditorView.stripMarkdownSyntax("Just a normal line") == "Just a normal line")
    }

    @Test func handlesCombinedSyntax() {
        #expect(EditorView.stripMarkdownSyntax("> - # Nested mess") == "Nested mess")
    }

    /// Whatever comes out still has to be a legal filename.
    @Test func resultSurvivesSanitising() {
        let title = EditorView.stripMarkdownSyntax("# My Title")
        #expect(DocumentStore.sanitize(title) == "My Title")

        // An empty derivation must not become a file named after punctuation.
        let empty = EditorView.stripMarkdownSyntax("#")
        #expect(DocumentStore.sanitize(empty) == "Untitled")
    }
}
