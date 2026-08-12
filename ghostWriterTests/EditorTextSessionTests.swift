//
//  EditorTextSessionTests.swift
//  ghostWriterTests
//

import Testing
import UIKit
@testable import ghostWriter

@MainActor
struct EditorTextSessionTests {

    @Test func nativeChangesDoNotPublishCompleteSnapshotsImmediately() {
        let session = EditorTextSession(initialText: "Initial")
        let textView = UITextView()
        session.attach(textView)
        var publishedSnapshots = 0
        session.onIdleSnapshot = { _ in publishedSnapshots += 1 }

        for pass in 1...1_000 {
            textView.selectedRange = NSRange(
                location: min(pass, textView.text.utf16.count),
                length: 0
            )
            session.textDidChange(in: textView)
        }

        #expect(session.revision == 1_000)
        #expect(publishedSnapshots == 0)
    }

    @Test func selectionChangesNeverRequestDocumentSnapshots() {
        let session = EditorTextSession(initialText: "A fairly long document")
        let textView = UITextView()
        session.attach(textView)
        var publishedSnapshots = 0
        session.onIdleSnapshot = { _ in publishedSnapshots += 1 }

        for location in 0...textView.text.utf16.count {
            textView.selectedRange = NSRange(location: location, length: 0)
            session.selectionDidChange(in: textView)
        }

        #expect(session.revision == 0)
        #expect(publishedSnapshots == 0)
    }

    @Test func idleBoundaryPublishesLatestTextOnce() async throws {
        let session = EditorTextSession(
            initialText: "Initial",
            idleDelay: 0.02
        )
        let textView = UITextView()
        session.attach(textView)
        var snapshots: [EditorTextSnapshot] = []
        session.onIdleSnapshot = { snapshots.append($0) }

        textView.text = "First"
        session.textDidChange(in: textView)
        textView.text = "Second"
        session.textDidChange(in: textView)

        try await Task.sleep(for: .milliseconds(80))

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.text == "Second")
        #expect(snapshots.first?.revision == 2)
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

    @Test func markedTextDefersIdlePublicationUntilCompositionEnds() async throws {
        let session = EditorTextSession(
            initialText: "",
            idleDelay: 0.02
        )
        let textView = UITextView()
        session.attach(textView)
        var snapshots: [EditorTextSnapshot] = []
        session.onIdleSnapshot = { snapshots.append($0) }

        textView.setMarkedText("typing", selectedRange: NSRange(location: 6, length: 0))
        #expect(textView.markedTextRange != nil)
        session.textDidChange(in: textView)

        try await Task.sleep(for: .milliseconds(70))
        #expect(snapshots.isEmpty)

        textView.unmarkText()
        try await Task.sleep(for: .milliseconds(70))

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.text == "typing")
    }

    @Test func deliberateReplacementUpdatesNativeAndSnapshotState() {
        let session = EditorTextSession(initialText: "Old")
        let textView = UITextView()
        session.attach(textView)

        session.replaceText(
            "A👻B",
            selection: TextSelection(location: 2, length: 0)
        )
        let snapshot = session.snapshot()

        #expect(textView.text == "A👻B")
        #expect(textView.selectedRange == NSRange(location: 3, length: 0))
        #expect(snapshot.text == "A👻B")
        #expect(snapshot.selection == TextSelection(location: 2, length: 0))
        #expect(snapshot.revision == 1)
    }
}
