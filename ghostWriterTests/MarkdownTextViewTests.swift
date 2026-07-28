//
//  MarkdownTextViewTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct MarkdownTextViewTests {

    @Test func programmaticCursorRequestProducesStatusSelection() {
        let text = "First\n## Destination"

        let selection = MarkdownTextView.selection(
            forRequestedCharacterOffset: 6,
            in: text
        )
        let status = DocumentStatus.calculate(text: text, selection: selection)

        #expect(selection == TextSelection(location: 6, length: 0))
        #expect(status.currentLine == 2)
        #expect(status.currentColumn == 1)
        #expect(status.headingLevel == 2)
    }

    @Test func programmaticCursorRequestClampsWithoutSplittingUnicode() {
        let text = "A👻B"

        let middle = MarkdownTextView.selection(
            forRequestedCharacterOffset: 2,
            in: text
        )
        let beyondEnd = MarkdownTextView.selection(
            forRequestedCharacterOffset: 50,
            in: text
        )

        #expect(middle.location == 2)
        #expect(MarkdownTextView.utf16Offset(for: middle.location, in: text) == 3)
        #expect(beyondEnd.location == 3)
    }
}
