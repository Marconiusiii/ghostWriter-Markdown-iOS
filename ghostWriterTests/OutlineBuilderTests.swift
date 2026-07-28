//
//  OutlineBuilderTests.swift
//  ghostWriterTests
//
//  The outline is essential navigation for long VoiceOver documents. These
//  tests pin down which headings appear and where selecting one moves the caret.
//

import Testing
@testable import ghostWriter

struct OutlineBuilderTests {

    @Test func buildsHeadingsInDocumentOrder() {
        let entries = OutlineBuilder.build(
            from: "# Introduction\nBody\n## Details\nMore\n### Finish"
        )

        #expect(entries.map(\.title) == ["Introduction", "Details", "Finish"])
        #expect(entries.map(\.level) == [1, 2, 3])
    }

    @Test func excludesHeadingSyntaxInsideCodeFences() {
        let entries = OutlineBuilder.build(
            from: "# Real\n```\n## Code, not a heading\n```\n## Also real"
        )

        #expect(entries.map(\.title) == ["Real", "Also real"])
    }

    @Test func removesOptionalClosingHashes() {
        let entries = OutlineBuilder.build(from: "## Chapter Two ##")
        #expect(entries.first?.title == "Chapter Two")
    }

    @Test func reportsCharacterOffsetForUnicodeDocuments() {
        let text = "👻 Introduction\n\n## Destination"
        let entries = OutlineBuilder.build(from: text)
        let destination = entries.first

        #expect(destination?.title == "Destination")
        #expect(destination?.characterOffset == "👻 Introduction\n\n".count)
    }
}
