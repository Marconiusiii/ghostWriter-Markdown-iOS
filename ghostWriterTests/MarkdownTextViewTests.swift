//
//  MarkdownTextViewTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct MarkdownTextViewTests {

    @Test func markedTextReplacementIsEligibleForFullAnnouncements() {
        #expect(
            MarkdownTypingEditEligibility.shouldTrack(
                isVoiceOverRunning: true,
                includesTypedStructureFeedback: true,
                rangeLength: 2,
                replacementText: "## ",
                belongsToMarkedTextComposition: true,
                isPerformingPaste: false
            )
        )
    }

    @Test func ordinaryReplacementsAndPasteRemainIneligible() {
        #expect(
            !MarkdownTypingEditEligibility.shouldTrack(
                isVoiceOverRunning: true,
                includesTypedStructureFeedback: true,
                rangeLength: 2,
                replacementText: "replacement",
                belongsToMarkedTextComposition: false,
                isPerformingPaste: false
            )
        )
        #expect(
            !MarkdownTypingEditEligibility.shouldTrack(
                isVoiceOverRunning: true,
                includesTypedStructureFeedback: true,
                rangeLength: 0,
                replacementText: "**bold**",
                belongsToMarkedTextComposition: false,
                isPerformingPaste: true
            )
        )
    }

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

    @Test func deferredListExitUsesUIKitUTF16RangesAfterUnicode() throws {
        let original = "👻\n* "
        let plan = try #require(
            ListContinuation.deferredReturnPlan(
                in: original,
                utf16Cursor: original.utf16.count,
                replacementText: "\r\n"
            )
        )
        let nativeText = original + "\r\n"
        let edit = try #require(
            ListContinuation.editAfterNativeReturn(
                plan,
                in: nativeText,
                selectedRange: NSRange(
                    location: nativeText.utf16.count,
                    length: 0
                )
            )
        )
        let updated = NSMutableString(string: nativeText)
        updated.replaceCharacters(in: edit.range, with: edit.replacementText)

        #expect(updated as String == "👻\n")
        #expect(edit.selectedRange.location == "👻\n".utf16.count)
    }
}
