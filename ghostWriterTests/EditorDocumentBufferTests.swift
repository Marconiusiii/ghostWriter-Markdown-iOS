//
//  EditorDocumentBufferTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct EditorDocumentBufferTests {

    @Test func initialSnapshotPreservesEmojiAndComposedText() async {
        let buffer = EditorDocumentBuffer(initialText: "A👻B")

        let snapshot = await buffer.snapshot()
        #expect(snapshot == EditorDocumentBufferSnapshot(text: "A👻B", revision: 0))
    }

    @Test func staleEditsCannotOverwriteANewerReplacement() async {
        let buffer = EditorDocumentBuffer(initialText: "old")

        buffer.replace(text: "new", revision: 5)
        buffer.replace(text: "stale", revision: 4)

        let snapshot = await buffer.snapshot()
        #expect(snapshot == EditorDocumentBufferSnapshot(text: "new", revision: 5))
    }

    @Test func boundaryReplacementPublishesOneCompleteSnapshot() async {
        let buffer = EditorDocumentBuffer(initialText: "")
        let text = String(repeating: "a", count: 10_000)
        buffer.replace(text: text, revision: 10_000)

        let snapshot = await buffer.snapshot()
        #expect(snapshot.text == text)
        #expect(snapshot.revision == 10_000)
    }
}
