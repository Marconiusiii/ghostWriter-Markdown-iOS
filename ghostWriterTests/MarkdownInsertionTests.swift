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

    @Test func inlineFormattingWrapsSelectionOrPlacesCaretBetweenMarkers() {
        let selected = MarkdownInsertion.bold(
            in: "Make this strong",
            selection: TextSelection(location: 5, length: 4)
        )
        let empty = MarkdownInsertion.italic(
            in: "Write ",
            selection: TextSelection(location: 6, length: 0)
        )
        let code = MarkdownInsertion.inlineCode(
            in: "Use value",
            selection: TextSelection(location: 4, length: 5)
        )

        #expect(selected.text == "Make **this** strong")
        #expect(selected.selection.location == 13)
        #expect(empty.text == "Write **")
        #expect(empty.selection.location == 7)
        #expect(code.text == "Use `value`")
    }

    @Test func headingReplacesAnExistingHeadingMarker() {
        let result = MarkdownInsertion.heading(
            level: 3,
            in: "Before\n# Title\nAfter",
            selection: TextSelection(location: 10, length: 0)
        )

        #expect(result.text == "Before\n### Title\nAfter")
        #expect(result.selection.location == 16)
    }

    @Test func lineActionsTransformEverySelectedLine() {
        let text = "One\nTwo\nThree"
        let quote = MarkdownInsertion.blockQuote(
            in: text,
            selection: TextSelection(location: 0, length: 7)
        )
        let numbered = MarkdownInsertion.numberedList(
            in: text,
            selection: TextSelection(location: 0, length: 7)
        )
        let tasks = MarkdownInsertion.taskList(
            in: "- One\n2. Two",
            selection: TextSelection(location: 0, length: 12)
        )

        #expect(quote.text == "> One\n> Two\nThree")
        #expect(numbered.text == "1. One\n2. Two\nThree")
        #expect(tasks.text == "- [ ] One\n- [ ] Two")
    }

    @Test func codeBlockPlacesCaretInsideAnEmptyFence() {
        let empty = MarkdownInsertion.codeBlock(
            in: "",
            selection: TextSelection(location: 0, length: 0)
        )
        let selected = MarkdownInsertion.codeBlock(
            in: "swift",
            selection: TextSelection(location: 0, length: 5)
        )

        #expect(empty.text == "```\n\n```")
        #expect(empty.selection.location == 4)
        #expect(selected.text == "```\nswift\n```")
        #expect(selected.selection.location == 13)
    }

    @Test func horizontalRulePreservesSurroundingParagraphBoundaries() {
        let result = MarkdownInsertion.horizontalRule(
            in: "BeforeAfter",
            selection: TextSelection(location: 6, length: 0)
        )

        #expect(result.text == "Before\n\n---\n\nAfter")
    }

    @Test func commandsApplyTheChosenPrimitive() {
        let heading = MarkdownInsertion.apply(
            .heading(level: 2),
            in: "Title",
            selection: TextSelection(location: 0, length: 0)
        )
        let strike = MarkdownInsertion.apply(
            .strikethrough,
            in: "Remove this",
            selection: TextSelection(location: 7, length: 4)
        )
        let link = MarkdownInsertion.apply(
            .link(label: "Home", address: "https://example.com"),
            in: "",
            selection: TextSelection(location: 0, length: 0)
        )

        #expect(heading.text == "## Title")
        #expect(strike.text == "Remove ~~this~~")
        #expect(link.text == "[Home](https://example.com)")
    }
}
