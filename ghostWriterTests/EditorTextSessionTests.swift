//
//  EditorTextSessionTests.swift
//  ghostWriterTests
//

import Testing
import UIKit
@testable import ghostWriter

@MainActor
struct EditorTextSessionTests {

    @Test func nativeChangesEnqueueDeltasWithoutPublishingSnapshots() async {
        let buffer = EditorDocumentBuffer(initialText: "")
        let session = EditorTextSession(initialText: "", documentBuffer: buffer)

        for pass in 0..<1_000 {
            session.willApplyEdit(
                range: NSRange(location: pass, length: 0),
                replacementText: "a"
            )
        }

        let snapshot = await buffer.snapshot()
        #expect(session.revision == 1_000)
        #expect(snapshot.text == String(repeating: "a", count: 1_000))
        #expect(snapshot.revision == 1_000)
    }

    @Test func selectionChangesNeverChangeTheDocumentBuffer() async {
        let buffer = EditorDocumentBuffer(initialText: "A fairly long document")
        let session = EditorTextSession(
            initialText: "A fairly long document",
            documentBuffer: buffer
        )
        let textView = UITextView()
        session.attach(textView)

        for location in 0...textView.text.utf16.count {
            textView.selectedRange = NSRange(location: location, length: 0)
            session.selectionDidChange(in: textView)
        }

        let snapshot = await buffer.snapshot()
        #expect(session.revision == 0)
        #expect(snapshot.text == "A fairly long document")
    }

    @Test func acceptedReplacementRangesBuildTheLatestTextOffMain() async {
        let buffer = EditorDocumentBuffer(initialText: "Initial")
        let session = EditorTextSession(initialText: "Initial", documentBuffer: buffer)

        session.willApplyEdit(
            range: NSRange(location: 0, length: 7),
            replacementText: "First"
        )
        session.willApplyEdit(
            range: NSRange(location: 0, length: 5),
            replacementText: "Second"
        )

        let snapshot = await buffer.snapshot()
        #expect(snapshot.text == "Second")
        #expect(snapshot.revision == 2)
    }

    @Test func explicitSnapshotConvertsUnicodeSelectionOnlyOnRequest() {
        let session = EditorTextSession(initialText: "A👻B")
        let textView = UITextView()
        session.attach(textView)
        textView.selectedRange = NSRange(location: 3, length: 0)
        session.selectionDidChange(in: textView)

        let snapshot = session.snapshot()

        #expect(snapshot.selection == TextSelection(location: 2, length: 0))
    }

    @Test func markedTextStyleReplacementsAreMirroredAsOrdinaryDeltas() async {
        let buffer = EditorDocumentBuffer(initialText: "")
        let session = EditorTextSession(initialText: "", documentBuffer: buffer)

        session.willApplyEdit(
            range: NSRange(location: 0, length: 0),
            replacementText: "typ"
        )
        session.willApplyEdit(
            range: NSRange(location: 0, length: 3),
            replacementText: "typing"
        )

        let snapshot = await buffer.snapshot()
        #expect(snapshot.text == "typing")
        #expect(snapshot.revision == 2)
    }

    @Test func deliberateReplacementUpdatesNativeAndBufferedState() async {
        let buffer = EditorDocumentBuffer(initialText: "Old")
        let session = EditorTextSession(initialText: "Old", documentBuffer: buffer)
        let textView = UITextView()
        session.attach(textView)

        session.replaceText(
            "A👻B",
            selection: TextSelection(location: 2, length: 0)
        )
        let nativeSnapshot = session.snapshot()
        let bufferedSnapshot = await buffer.snapshot()

        #expect(textView.text == "A👻B")
        #expect(textView.selectedRange == NSRange(location: 3, length: 0))
        #expect(nativeSnapshot.text == "A👻B")
        #expect(nativeSnapshot.selection == TextSelection(location: 2, length: 0))
        #expect(bufferedSnapshot.text == "A👻B")
        #expect(bufferedSnapshot.revision == 1)
    }
}
