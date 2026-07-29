//
//  LineNavigationTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct LineNavigationTests {

    @Test func firstLineStartsAtBeginning() {
        #expect(
            LineNavigation.destination(for: "1", in: "First\nSecond")
                == .success(0)
        )
    }

    @Test func laterLineReturnsCharacterOffset() {
        #expect(
            LineNavigation.destination(for: "3", in: "First\nSecond\nThird")
                == .success(13)
        )
    }

    @Test func unicodeCharactersCountAsSingleOffsets() {
        #expect(
            LineNavigation.destination(for: "2", in: "A👻\nDestination")
                == .success(3)
        )
    }

    @Test func trailingNewlineCreatesBlankFinalLine() {
        let text = "First\n"

        #expect(LineNavigation.lineCount(in: text) == 2)
        #expect(
            LineNavigation.destination(for: "2", in: text)
                == .success(text.count)
        )
    }

    @Test func emptyDocumentStillHasFirstLine() {
        #expect(LineNavigation.lineCount(in: "") == 1)
        #expect(LineNavigation.destination(for: "1", in: "") == .success(0))
    }

    @Test func surroundingWhitespaceIsAccepted() {
        #expect(
            LineNavigation.destination(for: " 2 ", in: "First\nSecond")
                == .success(6)
        )
    }

    @Test(arguments: ["", "word", "0", "-2", "1.5"])
    func invalidEntriesAreRejected(input: String) {
        #expect(
            LineNavigation.destination(for: input, in: "First\nSecond")
                == .failure(.invalidEntry(lineCount: 2))
        )
    }

    @Test func nonexistentLineReportsRequestedAndAvailableLines() {
        #expect(
            LineNavigation.destination(for: "4", in: "First\nSecond")
                == .failure(.lineDoesNotExist(requested: 4, lineCount: 2))
        )
    }

    @Test func carriageReturnLineEndingsAreRecognized() {
        #expect(LineNavigation.lineCount(in: "First\rSecond") == 2)
        #expect(
            LineNavigation.destination(for: "2", in: "First\rSecond")
                == .success(6)
        )
    }
}
