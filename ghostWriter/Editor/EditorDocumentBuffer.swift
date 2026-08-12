//
//  EditorDocumentBuffer.swift
//  ghostWriter
//
//  Holds document snapshots on a private serial queue for boundary saves. The
//  native text view remains completely authoritative while the writer types;
//  this buffer is updated only when an explicit action or lifecycle transition
//  requests a snapshot.
//

import Foundation

nonisolated struct EditorDocumentBufferSnapshot: Equatable, Sendable {
    let text: String
    let revision: Int
}

nonisolated final class EditorDocumentBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.marconius.ghostwriter.editor-buffer",
        qos: .utility
    )
    private var text: NSMutableString
    private var revision: Int

    init(
        initialText: String,
        initialRevision: Int = 0
    ) {
        text = NSMutableString(string: initialText)
        revision = initialRevision
    }

    /// Synchronizes at a deliberate action or lifecycle boundary. This is
    /// never called for ordinary typing callbacks.
    func replace(
        text newText: String,
        revision newRevision: Int
    ) {
        queue.async { [weak self] in
            guard let self, newRevision >= revision else { return }
            text.setString(newText)
            revision = newRevision
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

    private func makeSnapshot() -> EditorDocumentBufferSnapshot {
        EditorDocumentBufferSnapshot(text: text as String, revision: revision)
    }
}
