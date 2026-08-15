//
//  MarkdownTextViewTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
import UIKit
@testable import ghostWriter

struct MarkdownTextViewTests {

    @Test func editorAnnouncementsWaitForExistingVoiceOverSpeech() {
        let announcement = MarkdownEditorAnnouncement.queued("Bold applied.")
        let priority = announcement.attribute(
            .accessibilitySpeechAnnouncementPriority,
            at: 0,
            effectiveRange: nil
        ) as? UIAccessibilityPriority

        #expect(announcement.string == "Bold applied.")
        #expect(priority == .low)
    }

    @MainActor
    @Test func committedInsertionCallsTheNativeInputHook() {
        let textView = MarkdownEditorTextView()
        var commits: [String] = []
        textView.onCommittedTextInput = { commits.append($0) }

        textView.insertText("## ")

        #expect(commits == ["## "])
        #expect(textView.text == "## ")
    }

    @MainActor
    @Test func unmarkingCompositionCallsTheNativeInputHook() {
        let textView = MarkdownEditorTextView()
        var commits: [String] = []
        textView.onCommittedTextInput = { commits.append($0) }
        textView.setMarkedText(
            "**bold**",
            selectedRange: NSRange(location: 8, length: 0)
        )

        #expect(textView.markedTextRange != nil)
        textView.unmarkText()

        #expect(commits == ["**bold**"])
        #expect(textView.markedTextRange == nil)
        #expect(textView.text == "**bold**")
    }

    @Test func onlyTheLatestCommittedInputEvaluationIsAccepted() {
        var gate = MarkdownTypingCommitGate()

        let first = gate.issue()
        let second = gate.issue()

        #expect(!gate.accepts(first))
        #expect(gate.accepts(second))
        gate.invalidate()
        #expect(!gate.accepts(second))
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

    @Test func nativeCursorOffsetConvertsBackToCharacterOffset() {
        let text = "A👻B"

        #expect(
            MarkdownTextView.characterOffset(
                forUTF16Offset: 3,
                in: text
            ) == 2
        )
        #expect(
            MarkdownTextView.characterOffset(
                forUTF16Offset: 50,
                in: text
            ) == 3
        )
    }

    @MainActor
    @Test func physicalRightSwipeMovesToTheNextHeading() {
        let textView = MarkdownEditorTextView()
        textView.text = "# First\nBody\n## Second"
        textView.selectedRange = NSRange(location: 0, length: 0)
        var synchronizedSelection: NSRange?
        textView.onHeadingSwipeSelectionChanged = {
            synchronizedSelection = $0
        }

        let handled = textView.accessibilityScroll(.right)
        let expected = "# First\nBody\n".utf16.count

        #expect(handled)
        #expect(textView.selectedRange == NSRange(location: expected, length: 0))
        #expect(synchronizedSelection == textView.selectedRange)
    }

    @MainActor
    @Test func physicalLeftSwipeMovesToThePreviousHeading() {
        let textView = MarkdownEditorTextView()
        textView.text = "# First\nBody\n## Second"
        textView.selectedRange = NSRange(
            location: textView.text.utf16.count,
            length: 0
        )

        let handled = textView.accessibilityScroll(.left)
        let expected = "# First\nBody\n".utf16.count

        #expect(handled)
        #expect(textView.selectedRange == NSRange(location: expected, length: 0))
    }

    @MainActor
    @Test func headingSwipeFeedbackIncludesIndexTitleAndLevel() throws {
        let heading = try #require(
            OutlineBuilder.build(from: "# First\nBody\n## Second").last
        )

        let description = MarkdownEditorTextView.headingPositionDescription(
            destination: heading,
            position: 1,
            count: 2
        )

        #expect(description == "Heading 2 of 2, Second, heading level 2.")
    }

    @Test func headingSwipeFeedbackInterruptsAndRemainsInterruptible() {
        let announcement = MarkdownEditorTextView.headingPositionAnnouncement(
            "Heading 2 of 2, Second, heading level 2."
        )
        let priority = announcement.attribute(
            .accessibilitySpeechAnnouncementPriority,
            at: 0,
            effectiveRange: nil
        ) as? UIAccessibilityPriority

        #expect(priority == .default)
    }

    @Test func headingSwipeFeedbackUsesAnInterruptingAnnouncement() {
        #expect(
            MarkdownEditorTextView.headingFeedbackNotification
                == .announcement
        )
        #expect(
            MarkdownEditorTextView.headingFeedbackNotification
                != .pageScrolled
        )
    }

    @MainActor
    @Test func rapidHeadingSwipesTraverseEveryHeadingInBothDirections() {
        let textView = MarkdownEditorTextView()
        textView.text = "# One\nBody\n## Two\nBody\n### Three"
        textView.selectedRange = NSRange(location: 0, length: 0)

        let second = "# One\nBody\n".utf16.count
        let third = "# One\nBody\n## Two\nBody\n".utf16.count

        #expect(textView.accessibilityScroll(.right))
        #expect(textView.selectedRange.location == second)
        #expect(textView.accessibilityScroll(.right))
        #expect(textView.selectedRange.location == third)
        #expect(textView.accessibilityScroll(.left))
        #expect(textView.selectedRange.location == second)
        #expect(textView.accessibilityScroll(.left))
        #expect(textView.selectedRange.location == 0)
        #expect(textView.accessibilityScroll(.right))
        #expect(textView.selectedRange.location == second)
    }

    @MainActor
    @Test func disabledHeadingSwipesDoNotMoveTheInsertionPoint() {
        let textView = MarkdownEditorTextView()
        textView.text = "# First\n## Second"
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.headingSwipeNavigationEnabled = false

        _ = textView.accessibilityScroll(.left)

        #expect(textView.selectedRange == NSRange(location: 0, length: 0))
    }

    @MainActor
    @Test func verticalVoiceOverScrollingDoesNotMoveBetweenHeadings() {
        let textView = MarkdownEditorTextView()
        textView.text = "# First\n## Second"
        textView.selectedRange = NSRange(location: 0, length: 0)

        _ = textView.accessibilityScroll(.down)

        #expect(textView.selectedRange == NSRange(location: 0, length: 0))
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
