//
//  RecentlyDeletedView.swift
//  ghostWriter
//
//  Recoverable document deletion. Files remain ordinary files in the app's
//  Recently Deleted folder until the writer restores or permanently removes
//  them.
//

import SwiftUI

struct RecentlyDeletedView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pendingPermanentDeletion: Document?
    @State private var showingEmptyConfirmation = false
    @State private var focusAfterError: FocusTarget?
    @State private var focusRequestGate = FocusRestorationRequestGate()
    @AccessibilityFocusState private var focusedElement: FocusTarget?

    private enum FocusTarget: Hashable {
        case countHeading
        case document(URL)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(countDescription)
                    .font(.title3.bold())
                    .foregroundStyle(Color.ghostAccent)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .countHeading
                    )

                if deletedDocuments.isEmpty {
                    Text("Documents moved here can be restored until they are deleted permanently.")
                        .font(.body)
                        .foregroundStyle(Color.ghostMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    deletedList
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .background(Color.pageBackground)
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empty") {
                        focusRequestGate.invalidate()
                        showingEmptyConfirmation = true
                    }
                    .accessibilityLabel("Empty Recently Deleted")
                    .disabled(deletedDocuments.isEmpty)
                }
            }
        }
        .onAppear { store.refresh() }
        .alert("Delete Permanently?", isPresented: permanentDeletionBinding) {
            Button("Cancel", role: .cancel) {
                cancelPermanentDeletion()
            }
            Button("Delete Permanently", role: .destructive) {
                commitPermanentDeletion()
            }
            .accessibilityLabel(
                pendingPermanentDeletion.map {
                    "Delete Permanently \($0.displayName)"
                } ?? "Delete Permanently"
            )
        } message: {
            Text(
                pendingPermanentDeletion.map {
                    "\($0.displayName) will be permanently deleted. This cannot be undone."
                } ?? ""
            )
        }
        .alert("Empty Recently Deleted?", isPresented: $showingEmptyConfirmation) {
            Button("Cancel", role: .cancel) {
                restoreFocus(to: .countHeading)
            }
            Button("Empty", role: .destructive) {
                emptyRecentlyDeleted()
            }
        } message: {
            Text("Every document in Recently Deleted will be permanently deleted. This cannot be undone.")
        }
        .alert("ghostWriter Error", isPresented: errorBinding) {
            Button("OK") {
                dismissError()
            }
        } message: {
            Text(store.lastError ?? "An unknown error occurred.")
        }
    }

    private var deletedList: some View {
        List {
            ForEach(deletedDocuments) { document in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.ghostText)
                        Text("Modified \(DateFormatting.short(document.modified))")
                            .font(.caption)
                            .foregroundStyle(Color.ghostMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(document.displayName), modified \(DateFormatting.spoken(document.modified))"
                    )
                    .accessibilityHint("Deleted document")
                    .accessibilityAction(
                        named: "Restore \(document.displayName)"
                    ) {
                        restore(document)
                    }
                    .accessibilityAction(
                        named: "Delete Permanently \(document.displayName)"
                    ) {
                        beginPermanentDeletion(document)
                    }
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .document(document.url)
                    )

                    RecentlyDeletedActionsMenu(
                        document: document,
                        onRestore: { restore(document) },
                        onDeletePermanently: {
                            beginPermanentDeletion(document)
                        }
                    )
                    .buttonStyle(.bordered)
                }
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var deletedDocuments: [Document] {
        store.recentlyDeletedDocuments.sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
    }

    private var countDescription: String {
        let count = deletedDocuments.count
        return "\(count) \(count == 1 ? "deleted document" : "deleted documents")"
    }

    private func restore(_ document: Document) {
        focusRequestGate.invalidate()
        let nextTarget = focusAfterRemoving(document)
        focusAfterError = .document(document.url)

        guard let restoredURL = store.restore(document) else { return }
        EditorPositionStore.shared.migratePosition(
            from: document.url,
            to: restoredURL
        )
        focusAfterError = nil
        restoreFocus(to: availableFocus(nextTarget))
    }

    private func beginPermanentDeletion(_ document: Document) {
        focusRequestGate.invalidate()
        pendingPermanentDeletion = document
    }

    private func cancelPermanentDeletion() {
        guard let document = pendingPermanentDeletion else { return }
        pendingPermanentDeletion = nil
        restoreFocus(to: availableFocus(.document(document.url)))
    }

    private func commitPermanentDeletion() {
        guard let document = pendingPermanentDeletion else { return }
        let nextTarget = focusAfterRemoving(document)
        focusAfterError = .document(document.url)

        guard store.deletePermanently(document) else {
            pendingPermanentDeletion = nil
            return
        }
        EditorPositionStore.shared.removePosition(for: document.url)
        pendingPermanentDeletion = nil
        focusAfterError = nil
        restoreFocus(to: availableFocus(nextTarget))
    }

    private func emptyRecentlyDeleted() {
        focusRequestGate.invalidate()
        let documents = deletedDocuments
        focusAfterError = .countHeading

        for document in documents {
            guard store.deletePermanently(document) else { return }
            EditorPositionStore.shared.removePosition(for: document.url)
        }

        focusAfterError = nil
        restoreFocus(to: .countHeading)
    }

    private func focusAfterRemoving(_ document: Document) -> FocusTarget {
        guard let index = deletedDocuments.firstIndex(of: document) else {
            return .countHeading
        }
        if index + 1 < deletedDocuments.count {
            return .document(deletedDocuments[index + 1].url)
        }
        if index > 0 {
            return .document(deletedDocuments[index - 1].url)
        }
        return .countHeading
    }

    private func availableFocus(_ target: FocusTarget) -> FocusTarget {
        if case .document(let url) = target,
           !deletedDocuments.contains(where: { $0.url == url }) {
            return .countHeading
        }
        return target
    }

    private func restoreFocus(to target: FocusTarget) {
        let requestID = focusRequestGate.begin()
        focusedElement = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard focusRequestGate.permits(requestID) else { return }
            focusedElement = target
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard focusRequestGate.permits(requestID) else { return }
            focusedElement = target
        }
    }

    private func dismissError() {
        store.lastError = nil
        let target = availableFocus(focusAfterError ?? .countHeading)
        focusAfterError = nil
        restoreFocus(to: target)
    }

    private var permanentDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingPermanentDeletion != nil },
            set: {
                if !$0, pendingPermanentDeletion != nil {
                    cancelPermanentDeletion()
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: {
                if !$0, store.lastError != nil {
                    dismissError()
                }
            }
        )
    }
}

private struct RecentlyDeletedActionsMenu: View {
    let document: Document
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    var body: some View {
        Menu {
            Button(action: onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .accessibilityLabel("Restore \(document.displayName)")

            Button(role: .destructive, action: onDeletePermanently) {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
            .accessibilityLabel(
                "Delete Permanently \(document.displayName)"
            )
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Actions for \(document.displayName)")
    }
}
