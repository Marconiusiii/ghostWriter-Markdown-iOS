//
//  EditorDocumentBufferTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct EditorDocumentBufferTests {

    @Test func utf16EditsPreserveEmojiAndComposedText() async {
        let buffer = EditorDocumentBuffer(initialText: "A👻B")

        buffer.enqueue(
            EditorDocumentEdit(
                range: NSRange(location: 1, length: 2),
                replacementText: "é",
                revision: 1
            )
        )

        let snapshot = await buffer.snapshot()
        #expect(snapshot == EditorDocumentBufferSnapshot(text: "AéB", revision: 1))
    }

    @Test func staleEditsCannotOverwriteANewerReplacement() async {
        let buffer = EditorDocumentBuffer(initialText: "old")

        buffer.replace(text: "new", revision: 5, schedulesAutosave: false)
        buffer.enqueue(
            EditorDocumentEdit(
                range: NSRange(location: 0, length: 3),
                replacementText: "stale",
                revision: 4
            )
        )

        let snapshot = await buffer.snapshot()
        #expect(snapshot == EditorDocumentBufferSnapshot(text: "new", revision: 5))
    }

    @Test func debouncePublishesOnlyTheLatestBackgroundSnapshot() async throws {
        let buffer = EditorDocumentBuffer(initialText: "", autosaveDelay: 0.02)
        let recorder = SnapshotRecorder()
        buffer.setAutosaveHandler { snapshot in recorder.append(snapshot) }

        buffer.enqueue(
            EditorDocumentEdit(
                range: NSRange(location: 0, length: 0),
                replacementText: "a",
                revision: 1
            )
        )
        buffer.enqueue(
            EditorDocumentEdit(
                range: NSRange(location: 1, length: 0),
                replacementText: "b",
                revision: 2
            )
        )

        await recorder.waitForFirstSnapshot()
        #expect(recorder.snapshots == [
            EditorDocumentBufferSnapshot(text: "ab", revision: 2)
        ])
    }

    @Test func explicitResynchronizationDoesNotCancelPendingAutosave() async throws {
        let buffer = EditorDocumentBuffer(initialText: "", autosaveDelay: 0.02)
        let recorder = SnapshotRecorder()
        buffer.setAutosaveHandler { snapshot in recorder.append(snapshot) }

        buffer.enqueue(
            EditorDocumentEdit(
                range: NSRange(location: 0, length: 0),
                replacementText: "saved",
                revision: 1
            )
        )
        buffer.replace(text: "saved", revision: 1, schedulesAutosave: false)

        await recorder.waitForFirstSnapshot()
        #expect(recorder.snapshots == [
            EditorDocumentBufferSnapshot(text: "saved", revision: 1)
        ])
    }
}

private final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshots: [EditorDocumentBufferSnapshot] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var snapshots: [EditorDocumentBufferSnapshot] {
        lock.withLock { storedSnapshots }
    }

    func append(_ snapshot: EditorDocumentBufferSnapshot) {
        let continuations = lock.withLock {
            storedSnapshots.append(snapshot)
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        continuations.forEach { $0.resume() }
    }

    func waitForFirstSnapshot() async {
        if lock.withLock({ !storedSnapshots.isEmpty }) { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if storedSnapshots.isEmpty {
                    waiters.append(continuation)
                    return false
                }
                return true
            }
            if shouldResume { continuation.resume() }
        }
    }
}
