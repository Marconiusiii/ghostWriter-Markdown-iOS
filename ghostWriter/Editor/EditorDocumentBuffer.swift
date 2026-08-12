//
//  EditorDocumentBuffer.swift
//  ghostWriter
//
//  Mirrors accepted UITextView edits on a private serial queue. The native
//  text view remains authoritative for live input; this buffer exists so
//  autosave never has to copy the complete document from UIKit's main thread.
//

import Foundation

nonisolated struct EditorDocumentEdit: Equatable, Sendable {
    let range: NSRange
    let replacementText: String
    let revision: Int
}

nonisolated struct EditorDocumentBufferSnapshot: Equatable, Sendable {
    let text: String
    let revision: Int
}

nonisolated final class EditorDocumentBuffer: @unchecked Sendable {
    typealias AutosaveHandler = @Sendable (EditorDocumentBufferSnapshot) -> Void

    private let queue = DispatchQueue(
        label: "com.marconius.ghostwriter.editor-buffer",
        qos: .utility
    )
    private let autosaveDelay: TimeInterval
    private var text: NSMutableString
    private var revision: Int
    private var autosaveWorkItem: DispatchWorkItem?
    private var autosaveHandler: AutosaveHandler?

    init(
        initialText: String,
        initialRevision: Int = 0,
        autosaveDelay: TimeInterval = 1
    ) {
        text = NSMutableString(string: initialText)
        revision = initialRevision
        self.autosaveDelay = autosaveDelay
    }

    func setAutosaveHandler(_ handler: AutosaveHandler?) {
        queue.async { [weak self] in
            self?.autosaveHandler = handler
        }
    }

    func enqueue(_ edit: EditorDocumentEdit) {
        queue.async { [weak self] in
            guard let self else { return }
            guard edit.revision > revision else { return }
            guard edit.range.location <= text.length,
                  edit.range.length <= text.length - edit.range.location else {
                return
            }

            text.replaceCharacters(in: edit.range, with: edit.replacementText)
            revision = edit.revision
            scheduleAutosave()
        }
    }

    /// Resynchronizes after a deliberate whole-document operation. This is
    /// never called for ordinary typing.
    func replace(
        text newText: String,
        revision newRevision: Int,
        schedulesAutosave: Bool
    ) {
        queue.async { [weak self] in
            guard let self, newRevision >= revision else { return }
            text.setString(newText)
            revision = newRevision
            if schedulesAutosave {
                autosaveWorkItem?.cancel()
                scheduleAutosave()
            }
        }
    }

    func snapshot() async -> EditorDocumentBufferSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        returning: EditorDocumentBufferSnapshot(text: "", revision: 0)
                    )
                    return
                }
                continuation.resume(returning: makeSnapshot())
            }
        }
    }

    func cancelAutosave() {
        queue.async { [weak self] in
            self?.autosaveWorkItem?.cancel()
            self?.autosaveWorkItem = nil
        }
    }

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            autosaveWorkItem = nil
            autosaveHandler?(makeSnapshot())
        }
        autosaveWorkItem = workItem
        queue.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    private func makeSnapshot() -> EditorDocumentBufferSnapshot {
        EditorDocumentBufferSnapshot(text: text as String, revision: revision)
    }
}
