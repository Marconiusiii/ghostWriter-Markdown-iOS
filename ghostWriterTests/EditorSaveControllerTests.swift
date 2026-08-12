//
//  EditorSaveControllerTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct EditorSaveControllerTests {

    @Test func closeSettlementStillWaitsForTheGuardedSave() async throws {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let controller = EditorSaveController(initialText: "old", url: url)
        let saveGate = FirstSaveGate()
        var didSettle = false
        controller.configure { _, _, _ in
            await saveGate.pause()
            return .saved
        }

        controller.submit(
            EditorDocumentBufferSnapshot(text: "new", revision: 1),
            announce: false
        ) {
            didSettle = true
        }
        await saveGate.waitUntilPaused()
        #expect(!didSettle)

        await saveGate.resume()
        try await Task.sleep(for: .milliseconds(30))

        #expect(didSettle)
        #expect(controller.lastSavedRevision == 1)
    }

    @Test func boundarySaveWithoutAnnouncementDoesNotInvokeInterfaceCallbacks() async throws {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let controller = EditorSaveController(initialText: "old", url: url)
        var explicitFeedback = 0
        var failures = 0
        var conflicts = 0
        controller.onExplicitSave = { explicitFeedback += 1 }
        controller.onFailure = { _ in failures += 1 }
        controller.onConflict = { _ in conflicts += 1 }
        controller.configure { _, _, _ in .saved }

        controller.submit(
            EditorDocumentBufferSnapshot(text: "new", revision: 1),
            announce: false
        )
        try await Task.sleep(for: .milliseconds(30))

        #expect(controller.lastSavedText == "new")
        #expect(controller.lastSavedRevision == 1)
        #expect(explicitFeedback == 0)
        #expect(failures == 0)
        #expect(conflicts == 0)
    }

    @Test func newerRevisionIsSavedAfterAnInFlightRevision() async throws {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let controller = EditorSaveController(initialText: "zero", url: url)
        let recorder = SaveRecorder()
        let firstSaveGate = FirstSaveGate()
        controller.configure { text, _, expected in
            await recorder.append(text: text, expected: expected)
            if text == "one" { await firstSaveGate.pause() }
            return .saved
        }

        controller.submit(
            EditorDocumentBufferSnapshot(text: "one", revision: 1),
            announce: false
        )
        await firstSaveGate.waitUntilPaused()
        await withCheckedContinuation { continuation in
            controller.submit(
                EditorDocumentBufferSnapshot(text: "two", revision: 2),
                announce: false
            ) {
                continuation.resume()
            }
            Task { await firstSaveGate.resume() }
        }

        let saves = await recorder.saves
        #expect(saves.last?.text == "two")
        #expect(saves.last?.expected == "one")
        #expect(controller.lastSavedRevision == 2)
    }

    @Test func conflictIsSurfacedWithoutAdvancingSavedRevision() async throws {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let controller = EditorSaveController(initialText: "old", url: url)
        var conflict: EditorSaveConflict?
        controller.onConflict = { conflict = $0 }
        controller.configure { _, _, _ in .changedOnDisk("external") }

        controller.submit(
            EditorDocumentBufferSnapshot(text: "mine", revision: 1),
            announce: false
        )
        try await Task.sleep(for: .milliseconds(30))

        #expect(conflict == .changed("external"))
        #expect(controller.lastSavedText == "old")
        #expect(controller.lastSavedRevision == 0)
    }
}

private actor SaveRecorder {
    struct Save: Sendable {
        let text: String
        let expected: String
    }

    private(set) var saves: [Save] = []

    func append(text: String, expected: String) {
        saves.append(Save(text: text, expected: expected))
    }
}

private actor FirstSaveGate {
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        isPaused = true
        pauseWaiters.forEach { $0.resume() }
        pauseWaiters.removeAll()
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func waitUntilPaused() async {
        if isPaused { return }
        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
