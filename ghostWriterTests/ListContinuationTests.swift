//
//  ListContinuationTests.swift
//  ghostWriterTests
//
//  Covers the Return-key behaviour in lists. These are the rules a writer feels
//  constantly while typing, so they are worth pinning down precisely.
//

import Foundation
import Testing
@testable import ghostWriter

struct ListMarkerTests {

    @Test func parsesUnorderedMarkers() {
        for bullet in ["-", "*", "+"] {
            let marker = ListMarker(line: "\(bullet) Item")
            #expect(marker != nil)
            #expect(marker?.style == .unordered(Character(bullet)))
            #expect(marker?.content == "Item")
        }
    }

    @Test func parsesOrderedMarkers() {
        let marker = ListMarker(line: "3. Third")
        #expect(marker?.style == .ordered(3))
        #expect(marker?.content == "Third")
    }

    @Test func parsesParenthesisedOrderedMarkers() {
        let marker = ListMarker(line: "2) Second")
        #expect(marker?.style == .ordered(2))
    }

    @Test func preservesIndentExactly() {
        let tabbed = ListMarker(line: "\t\t- Nested")
        #expect(tabbed?.indent == "\t\t")

        let spaced = ListMarker(line: "    - Nested")
        #expect(spaced?.indent == "    ")
    }

    @Test func rejectsNonListLines() {
        #expect(ListMarker(line: "Just a paragraph") == nil)
        #expect(ListMarker(line: "# Heading") == nil)
        #expect(ListMarker(line: "") == nil)
    }

    /// A decimal number must not be mistaken for a list item, which would make
    /// typing prices or version numbers insert bullets.
    @Test func rejectsDecimalNumbers() {
        #expect(ListMarker(line: "1.5 kilograms") == nil)
    }

    /// A marker with no space after it is not a list item.
    @Test func requiresSpaceAfterMarker() {
        #expect(ListMarker(line: "-Item") == nil)
        #expect(ListMarker(line: "1.Item") == nil)
    }

    @Test func parsesTaskBoxes() {
        let unchecked = ListMarker(line: "- [ ] Todo")
        #expect(unchecked?.taskBox == "[ ]")
        #expect(unchecked?.content == "Todo")

        let checked = ListMarker(line: "- [x] Done")
        #expect(checked?.taskBox == "[x]")
        #expect(checked?.content == "Done")
    }

    @Test func nextItemIncrementsOrderedNumber() {
        let marker = ListMarker(line: "  4. Fourth")
        #expect(marker?.nextItemPrefix == "  5. ")
    }

    @Test func nextItemRepeatsBullet() {
        let marker = ListMarker(line: "\t* Item")
        #expect(marker?.nextItemPrefix == "\t* ")
    }

    /// A new task item should start unchecked even when continuing from a
    /// completed one.
    @Test func nextTaskItemIsUnchecked() {
        let marker = ListMarker(line: "- [x] Done")
        #expect(marker?.nextItemPrefix == "- [ ] ")
    }
}

struct ListContinuationTests {

    @Test func markedTextReturnContinuesAfterNativeLineBreak() throws {
        let original = "* First"
        let plan = try #require(
            ListContinuation.deferredReturnPlan(
                in: original,
                utf16Cursor: original.utf16.count,
                replacementText: "\n"
            )
        )
        let nativeText = original + "\n"
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

        #expect(applying(edit, to: nativeText) == "* First\n* ")
    }

    @Test func secondMarkedTextReturnEndsTheEmptyList() throws {
        let original = "* First\n* "
        let plan = try #require(
            ListContinuation.deferredReturnPlan(
                in: original,
                utf16Cursor: original.utf16.count,
                replacementText: "\n"
            )
        )
        let nativeText = original + "\n"
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

        #expect(applying(edit, to: nativeText) == "* First\n")
        #expect(edit.selectedRange == NSRange(location: 8, length: 0))
    }

    @Test func deferredReturnSupportsOrderedNestedAndTaskLists() throws {
        let cases = [
            ("2. Item", "2. Item\n3. "),
            ("  * Nested", "  * Nested\n  * "),
            ("- [x] Done", "- [x] Done\n- [ ] ")
        ]

        for (original, expected) in cases {
            let plan = try #require(
                ListContinuation.deferredReturnPlan(
                    in: original,
                    utf16Cursor: original.utf16.count,
                    replacementText: "\r"
                )
            )
            // UITextView normalizes the Return representation to a line feed
            // in its stored text even when the input callback reports CR.
            let nativeText = original + "\n"
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
            #expect(applying(edit, to: nativeText) == expected)
        }
    }

    @Test func deferredPlanCannotModifyAnUnexpectedNativeResult() throws {
        let original = "* First\n* "
        let plan = try #require(
            ListContinuation.deferredReturnPlan(
                in: original,
                utf16Cursor: original.utf16.count,
                replacementText: "\n"
            )
        )

        #expect(
            ListContinuation.editAfterNativeReturn(
                plan,
                in: original + "x",
                selectedRange: NSRange(
                    location: original.utf16.count + 1,
                    length: 0
                )
            ) == nil
        )
    }

    @Test func continuesUnorderedList() {
        let text = "- First"
        let result = ListContinuation.handleReturn(in: text, cursor: text.count)
        #expect(result?.text == "- First\n- ")
        #expect(result?.cursor == 10)
    }

    @Test func continuesOrderedListWithNextNumber() {
        let text = "1. First"
        let result = ListContinuation.handleReturn(in: text, cursor: text.count)
        #expect(result?.text == "1. First\n2. ")
    }

    @Test func preservesNestingWhenContinuing() {
        let text = "  - Nested"
        let result = ListContinuation.handleReturn(in: text, cursor: text.count)
        #expect(result?.text == "  - Nested\n  - ")
    }

    /// Pressing Return on an empty list item ends the list rather than adding
    /// another empty bullet. This matches the web app and is the behaviour that
    /// lets a writer type their way out of a list without reaching for delete.
    @Test func emptyItemEndsList() {
        let text = "- First\n- "
        let result = ListContinuation.handleReturn(in: text, cursor: text.count)
        #expect(result?.text == "- First\n")
        #expect(result?.cursor == 8)
    }

    @Test func emptyOrderedItemEndsList() {
        let text = "1. First\n2. "
        let result = ListContinuation.handleReturn(in: text, cursor: text.count)
        #expect(result?.text == "1. First\n")
    }

    /// Not a list, so the caller should insert a plain newline itself.
    @Test func returnsNilForPlainParagraph() {
        let text = "Just writing"
        #expect(ListContinuation.handleReturn(in: text, cursor: text.count) == nil)
    }

    /// Splitting an item mid-line should carry the remaining text onto the new
    /// item rather than losing it.
    @Test func splitsItemAtCursor() {
        let text = "- FirstSecond"
        let result = ListContinuation.handleReturn(in: text, cursor: 7)
        #expect(result?.text == "- First\n- Second")
    }

    @Test func continuesTaskList() {
        let text = "- [ ] Todo"
        let result = ListContinuation.handleReturn(in: text, cursor: text.count)
        #expect(result?.text == "- [ ] Todo\n- [ ] ")
    }

    @Test func handlesCursorAtStartOfText() {
        #expect(ListContinuation.handleReturn(in: "", cursor: 0) == nil)
    }

    private func applying(
        _ edit: DeferredListReturnEdit,
        to text: String
    ) -> String {
        let updated = NSMutableString(string: text)
        updated.replaceCharacters(
            in: edit.range,
            with: edit.replacementText
        )
        return updated as String
    }
}

struct RenumberingTests {

    @Test func renumbersOutOfOrderList() {
        let text = "1. One\n1. Two\n1. Three"
        #expect(ListContinuation.renumberOrderedLists(in: text) == "1. One\n2. Two\n3. Three")
    }

    @Test func leavesUnorderedListsAlone() {
        let text = "- One\n- Two"
        #expect(ListContinuation.renumberOrderedLists(in: text) == text)
    }

    /// Nested lists are numbered independently of their parent.
    @Test func numbersNestedListsSeparately() {
        let text = "1. One\n  1. Sub one\n  5. Sub two\n2. Two"
        let expected = "1. One\n  1. Sub one\n  2. Sub two\n2. Two"
        #expect(ListContinuation.renumberOrderedLists(in: text) == expected)
    }

    /// A blank line separates two distinct lists, so the second restarts at one.
    @Test func blankLineStartsNewList() {
        let text = "1. One\n2. Two\n\n5. Fresh start"
        let expected = "1. One\n2. Two\n\n1. Fresh start"
        #expect(ListContinuation.renumberOrderedLists(in: text) == expected)
    }

    @Test func preservesContentAndIndent() {
        let text = "  3. Item with **bold**"
        #expect(ListContinuation.renumberOrderedLists(in: text) == "  1. Item with **bold**")
    }
}
