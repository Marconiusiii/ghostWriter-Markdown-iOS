//
//  MarkdownInsertionTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct MarkdownInsertionTests {

    @Test func linkReplacesTheCurrentSelectionAndMovesTheCaret() {
        let result = MarkdownInsertion.link(
            in: "Read this today",
            selection: TextSelection(location: 5, length: 4),
            label: "this",
            address: "https://example.com"
        )

        #expect(result.text == "Read [this](https://example.com) today")
        #expect(result.selection.location == 32)
        #expect(result.selection.length == 0)
    }

    @Test func selectedTextUsesHumanCharacterOffsets() {
        let selected = MarkdownInsertion.selectedText(
            in: "A👻BC",
            selection: TextSelection(location: 1, length: 2)
        )

        #expect(selected == "👻B")
    }

    @Test func imageCanUseEmptyAlternativeTextForDecoration() {
        let result = MarkdownInsertion.image(
            in: "Before  after",
            selection: TextSelection(location: 7, length: 0),
            alternativeText: "",
            address: "https://example.com/image.jpg"
        )

        #expect(result.text == "Before ![](https://example.com/image.jpg) after")
    }

    @Test func addressesAreTrimmedAndUnsafeDelimitersAreEncoded() {
        let result = MarkdownInsertion.link(
            in: "",
            selection: TextSelection(location: 0, length: 0),
            label: "Example",
            address: " https://example.com/a file(1) "
        )

        #expect(result.text == "[Example](https://example.com/a%20file%281%29)")
    }

    @Test func outOfRangeSelectionsAreSafelyClamped() {
        let result = MarkdownInsertion.link(
            in: "Draft",
            selection: TextSelection(location: 99, length: 10),
            label: "Source",
            address: "https://example.com"
        )

        #expect(result.text == "Draft[Source](https://example.com)")
    }
}
