import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct HelpManualEditingTests {
    @Test func automaticRequestsCannotPersistManualEditsBeforeOrAfterExplicitSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Original".write(to: url, atomically: true, encoding: .utf8)
        let controller = EditorSaveController(initialText: "Original", url: url, requiresExplicitSave: true)
        var writes = 0
        var implicitlyClosed = false
        controller.configure { text, destination, expected in
            guard (try? String(contentsOf: destination, encoding: .utf8)) == expected else { return .changedOnDisk("External") }
            do { try text.write(to: destination, atomically: true, encoding: .utf8); writes += 1; return .saved }
            catch { return .failed }
        }
        let edited = EditorDocumentBufferSnapshot(text: "Edited", revision: 1)
        // Backgrounding, rendering, and disappearing all use unannounced saves.
        for _ in 0..<3 { controller.submit(edited, announce: false) { implicitlyClosed = true } }
        #expect(writes == 0)
        #expect(!implicitlyClosed)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Original")
        await withCheckedContinuation { continuation in
            controller.submit(edited, announce: true) { continuation.resume() }
        }
        #expect(writes == 1)
        #expect(try String(contentsOf: url, encoding: .utf8) == "Edited")
        controller.submit(EditorDocumentBufferSnapshot(text: "Unsaved later edits", revision: 2), announce: false)
        #expect(writes == 1)
        #expect(controller.lastSavedText == "Edited")
        #expect(try String(contentsOf: url, encoding: .utf8) == "Edited")
    }

    @Test func failedExplicitSaveDoesNotCloseOrReplaceSavedBaseline() async {
        let controller = EditorSaveController(initialText: "Original", url: URL(fileURLWithPath: "/manual.md"), requiresExplicitSave: true)
        controller.configure { _, _, _ in .failed }
        var closed = false
        await withCheckedContinuation { continuation in
            controller.onFailure = { _ in continuation.resume() }
            controller.submit(EditorDocumentBufferSnapshot(text: "Edited", revision: 1), announce: true) { closed = true }
        }
        #expect(!closed)
        #expect(controller.lastSavedText == "Original")
        #expect(controller.hasUnsavedChanges(comparedTo: 1))
    }

    @Test func ordinaryDocumentStillAllowsAutomaticSaving() async {
        let controller = EditorSaveController(initialText: "Original", url: URL(fileURLWithPath: "/ordinary.md"))
        controller.configure { _, _, _ in .saved }
        await withCheckedContinuation { continuation in
            controller.submit(EditorDocumentBufferSnapshot(text: "Edited", revision: 1), announce: false) { continuation.resume() }
        }
        #expect(controller.lastSavedText == "Edited")
    }

    @Test func unchangedAndUndoneTextDoesNotNeedAnExitPrompt() {
        #expect(!HelpManualEditing.needsSavePrompt(current: "Original", saved: "Original"))
        #expect(HelpManualEditing.needsSavePrompt(current: "Original with edits", saved: "Original"))
        #expect(!HelpManualEditing.needsSavePrompt(current: "Saved edits", saved: "Saved edits"))
    }

    #if os(iOS)
    @Test func installingAgainKeepsExplicitlySavedManual() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = HelpManualDocument.libraryURL(in: root)
        try "My saved annotations".write(to: url, atomically: true, encoding: .utf8)
        let store = DocumentStore(directory: root)
        let reopened = try await HelpManualDocument.installIfNeeded(in: store)
        #expect(reopened == url)
        #expect(reopened.lastPathComponent == "ghostWriter Help Manual.md")
        #expect(HelpManualDocument.isManual(reopened))
        #expect(try String(contentsOf: reopened, encoding: .utf8) == "My saved annotations")
    }
    #endif
}
