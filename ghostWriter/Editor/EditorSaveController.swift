//
//  EditorSaveController.swift
//  ghostWriter
//
//  Serializes editor save requests without publishing routine autosave state
//  into SwiftUI. Only a conflict, failure, or explicit completion crosses back
//  into the view.
//

import Foundation

nonisolated enum EditorSaveConflict: Equatable, Sendable {
    case changed(String)
    case missing
}

@MainActor
final class EditorSaveController {
    typealias SaveOperation = @MainActor @Sendable (
        _ text: String,
        _ url: URL,
        _ expectedContents: String
    ) async -> GuardedSaveResult

    private struct Request {
        let snapshot: EditorDocumentBufferSnapshot
        let url: URL
    }

    private var saveOperation: SaveOperation?
    private var pendingRequest: Request?
    private var saving = false
    private var latestSubmittedRevision: Int
    private var announcementRequested = false
    private var settlementCallbacks: [() -> Void] = []

    private(set) var lastSavedText: String
    private(set) var lastSavedRevision: Int
    var currentURL: URL?
    var onConflict: ((EditorSaveConflict) -> Void)?
    var onFailure: ((_ explicitSave: Bool) -> Void)?
    var onExplicitSave: (() -> Void)?

    init(initialText: String, initialRevision: Int = 0, url: URL?) {
        lastSavedText = initialText
        lastSavedRevision = initialRevision
        latestSubmittedRevision = initialRevision
        currentURL = url
    }

    var isSaving: Bool { saving || pendingRequest != nil }

    func configure(saveOperation: @escaping SaveOperation) {
        self.saveOperation = saveOperation
        drainIfNeeded()
    }

    func submitAutosave(_ snapshot: EditorDocumentBufferSnapshot) {
        submit(snapshot, announce: false)
    }

    func submit(
        _ snapshot: EditorDocumentBufferSnapshot,
        announce: Bool,
        whenSettled: (() -> Void)? = nil
    ) {
        if announce { announcementRequested = true }
        if let whenSettled { settlementCallbacks.append(whenSettled) }

        guard let url = currentURL else {
            settleIfPossible()
            return
        }

        if snapshot.revision > latestSubmittedRevision {
            latestSubmittedRevision = snapshot.revision
            pendingRequest = Request(snapshot: snapshot, url: url)
        } else if snapshot.revision > lastSavedRevision,
                  pendingRequest == nil,
                  !saving {
            pendingRequest = Request(snapshot: snapshot, url: url)
        }

        drainIfNeeded()
    }

    func hasUnsavedChanges(comparedTo revision: Int) -> Bool {
        revision != lastSavedRevision
    }

    func resetSaved(text: String, revision: Int) {
        pendingRequest = nil
        lastSavedText = text
        lastSavedRevision = revision
        latestSubmittedRevision = revision
        announcementRequested = false
        settlementCallbacks.removeAll()
    }

    func cancelPending() {
        pendingRequest = nil
        announcementRequested = false
        settlementCallbacks.removeAll()
    }

    private func drainIfNeeded() {
        guard !saving, pendingRequest != nil, saveOperation != nil else {
            settleIfPossible()
            return
        }
        saving = true
        Task { await drain() }
    }

    private func drain() async {
        while let request = pendingRequest, let saveOperation {
            pendingRequest = nil
            let expectedContents = lastSavedText

            switch await saveOperation(
                request.snapshot.text,
                request.url,
                expectedContents
            ) {
            case .saved:
                lastSavedText = request.snapshot.text
                lastSavedRevision = request.snapshot.revision
            case .changedOnDisk(let externalText):
                saving = false
                cancelPending()
                onConflict?(.changed(externalText))
                return
            case .missing:
                saving = false
                cancelPending()
                onConflict?(.missing)
                return
            case .failed:
                let wasExplicit = announcementRequested
                saving = false
                cancelPending()
                onFailure?(wasExplicit)
                return
            }
        }

        saving = false
        settleIfPossible()
    }

    private func settleIfPossible() {
        guard !saving, pendingRequest == nil else { return }

        if announcementRequested {
            announcementRequested = false
            onExplicitSave?()
        }

        let callbacks = settlementCallbacks
        settlementCallbacks.removeAll()
        callbacks.forEach { $0() }
    }
}
