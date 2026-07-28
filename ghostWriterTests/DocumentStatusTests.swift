//
//  DocumentStatusTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct DocumentStatusTests {

    @Test func emptyDocumentHasOneLineAndFirstColumn() {
        let status = DocumentStatus.calculate(
            text: "",
            selection: TextSelection(location: 0, length: 0)
        )

        #expect(status.currentLine == 1)
        #expect(status.currentColumn == 1)
        #expect(status.lineCount == 1)
        #expect(status.wordCount == 0)
        #expect(status.characterCount == 0)
    }

    @Test func positionAndCountsUseHumanCharacterOffsets() {
        let text = "First line\n👻 two words"
        let status = DocumentStatus.calculate(
            text: text,
            selection: TextSelection(location: 13, length: 0)
        )

        #expect(status.currentLine == 2)
        #expect(status.currentColumn == 3)
        #expect(status.lineCount == 2)
        #expect(status.wordCount == 5)
        #expect(status.characterCount == 22)
    }

    @Test func headingLevelIsOnlyPresentOnAHeadingLine() {
        let text = "Paragraph\n### A heading"

        let paragraph = DocumentStatus.calculate(
            text: text,
            selection: TextSelection(location: 0, length: 0)
        )
        let heading = DocumentStatus.calculate(
            text: text,
            selection: TextSelection(location: 10, length: 0)
        )

        #expect(paragraph.headingLevel == nil)
        #expect(heading.headingLevel == 3)
    }

    @Test func markdownInsideCodeFenceIsNotReportedAsAHeading() {
        let text = "```\n# Not a heading\n```"
        let status = DocumentStatus.calculate(
            text: text,
            selection: TextSelection(location: 4, length: 0)
        )

        #expect(status.headingLevel == nil)
    }

    @Test func selectionCountsAndDescriptionRespectOptions() {
        let text = "One two three"
        let status = DocumentStatus.calculate(
            text: text,
            selection: TextSelection(location: 4, length: 9)
        )
        let options = DocumentStatusOptions(
            lineAndColumn: false,
            lineCount: false,
            wordCount: false,
            characterCount: false,
            headingLevel: false,
            selectedWordCount: true,
            selectedCharacterCount: true
        )

        #expect(status.selectedWordCount == 2)
        #expect(status.selectedCharacterCount == 9)
        #expect(status.description(options: options) == "2 selected words, 9 selected characters")
    }

    @Test func noChosenMetricsProducesAUsefulFocusStop() {
        let status = DocumentStatus.calculate(
            text: "Text",
            selection: TextSelection(location: 0, length: 0)
        )
        let options = DocumentStatusOptions(
            lineAndColumn: false,
            lineCount: false,
            wordCount: false,
            characterCount: false,
            headingLevel: false,
            selectedWordCount: false,
            selectedCharacterCount: false
        )

        #expect(status.description(options: options) == "No status information selected")
    }
}
