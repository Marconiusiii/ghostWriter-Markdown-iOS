//
//  IndentationTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct IndentationTests {

    @Test func indentsSingleLine() {
        let result = Indentation.indent(
            text: "Hello",
            selection: TextSelection(location: 0, length: 0),
            unit: .twoSpaces
        )
        #expect(result.text == "  Hello")
    }

    @Test func indentsWithTabs() {
        let result = Indentation.indent(
            text: "Hello",
            selection: TextSelection(location: 0, length: 0),
            unit: .tab
        )
        #expect(result.text == "\tHello")
    }

    /// Every line the selection touches is indented, not just the first.
    @Test func indentsAllLinesInSelection() {
        let text = "One\nTwo\nThree"
        let result = Indentation.indent(
            text: text,
            selection: TextSelection(location: 0, length: text.count),
            unit: .twoSpaces
        )
        #expect(result.text == "  One\n  Two\n  Three")
    }

    /// A selection that merely clips into a line still indents that whole line,
    /// because indentation is a line-level operation.
    @Test func indentsPartiallySelectedLines() {
        let text = "One\nTwo"
        let result = Indentation.indent(
            text: text,
            selection: TextSelection(location: 2, length: 3),
            unit: .twoSpaces
        )
        #expect(result.text == "  One\n  Two")
    }

    @Test func outdentsSingleLine() {
        let result = Indentation.outdent(
            text: "  Hello",
            selection: TextSelection(location: 0, length: 0),
            unit: .twoSpaces
        )
        #expect(result.text == "Hello")
    }

    /// Outdenting a line that is already flush left must not eat its content.
    @Test func outdentAtZeroIsSafe() {
        let result = Indentation.outdent(
            text: "Hello",
            selection: TextSelection(location: 0, length: 0),
            unit: .twoSpaces
        )
        #expect(result.text == "Hello")
    }

    @Test func outdentRemovesTabAsFullLevel() {
        let result = Indentation.outdent(
            text: "\tHello",
            selection: TextSelection(location: 0, length: 0),
            unit: .fourSpaces
        )
        #expect(result.text == "Hello")
    }

    /// Odd indentation should still outdent rather than refusing.
    @Test func outdentHandlesPartialIndent() {
        let result = Indentation.outdent(
            text: " Hello",
            selection: TextSelection(location: 0, length: 0),
            unit: .fourSpaces
        )
        #expect(result.text == "Hello")
    }

    @Test func indentThenOutdentRoundTrips() {
        let original = "One\n  Two\n\tThree"
        let selection = TextSelection(location: 0, length: original.count)

        let indented = Indentation.indent(text: original, selection: selection, unit: .twoSpaces)
        let outdented = Indentation.outdent(
            text: indented.text,
            selection: indented.selection,
            unit: .twoSpaces
        )
        #expect(outdented.text == original)
    }

    /// The caret should stay with the text it was next to, not jump to the
    /// start of the line.
    @Test func caretFollowsTextWhenIndenting() {
        let result = Indentation.indent(
            text: "Hello",
            selection: TextSelection(location: 5, length: 0),
            unit: .twoSpaces
        )
        #expect(result.selection.location == 7)
    }

    @Test func announcesResultingLevel() {
        let result = Indentation.indent(
            text: "  Hello",
            selection: TextSelection(location: 0, length: 0),
            unit: .twoSpaces
        )
        #expect(result.announcement == "Indented to level 2.")
    }

    @Test func announcesOutdentLevel() {
        let result = Indentation.outdent(
            text: "  Hello",
            selection: TextSelection(location: 0, length: 0),
            unit: .twoSpaces
        )
        #expect(result.announcement == "Outdented to level 0.")
    }

    /// Selections beyond the end of the text must be clamped rather than
    /// crashing, since a stale selection can arrive after an external edit.
    @Test func clampsOutOfRangeSelection() {
        let result = Indentation.indent(
            text: "Hi",
            selection: TextSelection(location: 99, length: 99),
            unit: .twoSpaces
        )
        #expect(result.text == "  Hi")
    }
}
