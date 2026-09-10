//
//  RecentlyDeletedView.swift
//  ghostWriter
//
//  Recoverable document deletion. Files remain ordinary files in the app's
//  Recently Deleted folder until the writer restores or permanently removes
//  them.
//

import SwiftUI
import UIKit

struct RecentlyDeletedView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var libraryMetadata
    @Environment(\.dismiss) private var dismiss

    @State private var pendingPermanentDeletion: DeletedLibraryItem?
    @State private var showingEmptyConfirmation = false
    @State private var statusMessage = ""
    /// Reading `store.recentlyDeletedItems` decodes one JSON deletion record
    /// per item from disk. Sorting that on every body evaluation is what made
    /// this screen lag, so the rows are built once per change instead.
    @State private var deletedItems: [DeletedLibraryItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                // Back comes first in both code and screen order, so it is the
                // first thing reached when swiping into the screen.
                Button("Back") { dismiss() }
                    .buttonStyle(.bordered)

                Text("Recently Deleted")
                    .font(.title.bold())
                    .foregroundStyle(Color.ghostAccent)
                    .accessibilityAddTraits(.isHeader)

                Text(countDescription)
                    .font(.title3.bold())
                    .foregroundStyle(Color.ghostAccent)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.ghostMuted)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                if deletedItems.isEmpty {
                    Text("Documents and folders moved here can be restored until they are deleted permanently.")
                        .font(.body)
                        .foregroundStyle(Color.ghostMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    deletedList
                }

                Button("Empty Recently Deleted", role: .destructive) {
                    showingEmptyConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(deletedItems.isEmpty)

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
        .onAppear {
            store.refresh()
            rebuildDeletedItems()
        }
        .onChange(of: store.recentlyDeletedRevision) { _, _ in
            rebuildDeletedItems()
        }
        .alert("Delete Permanently?", isPresented: permanentDeletionBinding) {
            Button("Cancel", role: .cancel) {
                cancelPermanentDeletion()
            }
            Button(
                pendingPermanentDeletion.map {
                    "Delete \($0.displayName) Permanently"
                } ?? "Delete Permanently",
                role: .destructive
            ) {
                commitPermanentDeletion()
            }
        } message: {
            Text(
                pendingPermanentDeletion.map {
                    "\($0.displayName) will be permanently deleted. This cannot be undone."
                } ?? ""
            )
        }
        .alert("Empty Recently Deleted?", isPresented: $showingEmptyConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Empty", role: .destructive) {
                emptyRecentlyDeleted()
            }
        } message: {
            Text("Every item in Recently Deleted will be permanently deleted. This cannot be undone.")
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
            ForEach(deletedItems) { item in
                deletedRow(item)
                    .listRowInsets(
                        EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// The whole row is one button; Restore is the primary action, so
    /// activating a row restores it rather than opening a menu first.
    ///
    /// Three affordances reach the same two actions: swipe actions and a
    /// long-press context menu for sighted use, and VoiceOver custom actions.
    /// SwiftUI publishes both the swipe actions and the context menu to
    /// VoiceOver automatically, which is what announced each action three
    /// times. The context menu is hidden from accessibility so it stays a
    /// pointer affordance only, leaving the swipe actions as the single
    /// source of the VoiceOver actions.
    private func deletedRow(_ item: DeletedLibraryItem) -> some View {
        let primaryRow = Button {
            restore(item)
        } label: {
            DeletedItemRow(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)

        let leadingSwipeRow = primaryRow
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    restore(item)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(Color.controlFill)
            }

        let swipeRow = leadingSwipeRow
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    beginPermanentDeletion(item)
                } label: {
                    Label("Delete Permanently", systemImage: "trash.slash")
                }
            }

        return swipeRow.contextMenu {
            Button {
                restore(item)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }

            Button(role: .destructive) {
                beginPermanentDeletion(item)
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
        }
    }

    /// Rebuilds the cached rows. Called on appear and whenever the store
    /// reports the Recently Deleted contents changed.
    private func rebuildDeletedItems() {
        deletedItems = store.recentlyDeletedItems.sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
    }

    private var countDescription: String {
        let count = deletedItems.count
        return count == 1
            ? String(localized: "1 deleted item")
            : String(localized: "\(count) deleted items")
    }

    private func restore(_ item: DeletedLibraryItem) {
        let restoredURL: URL?
        switch item.item {
        case .document(let document):
            restoredURL = store.restore(document)
            if let restoredURL {
                EditorPositionStore.shared.migratePosition(from: document.url, to: restoredURL)
                libraryMetadata.migrateMetadata(from: document.url, to: restoredURL)
            }
        case .folder(let folder):
            let pairs = store.documentMovePairs(
                fromFolder: folder.url,
                toFolder: folder.url
            )
            restoredURL = store.restore(folder)
            if let restoredURL {
                migrateFolderMetadata(
                    pairs,
                    fromRoot: folder.url,
                    toRoot: restoredURL
                )
            }
        }
        guard restoredURL != nil else { return }
        rebuildDeletedItems()

        announceSuccess("\(item.displayName) restored")
    }

    private func beginPermanentDeletion(_ item: DeletedLibraryItem) {
        pendingPermanentDeletion = item
    }

    private func cancelPermanentDeletion() {
        pendingPermanentDeletion = nil
    }

    private func commitPermanentDeletion() {
        guard let item = pendingPermanentDeletion else { return }

        let deleted: Bool
        switch item.item {
        case .document(let document):
            deleted = store.deletePermanently(document)
            if deleted {
                EditorPositionStore.shared.removePosition(for: document.url)
                libraryMetadata.removeMetadata(for: document.url)
            }
        case .folder(let folder):
            let pairs = store.documentMovePairs(
                fromFolder: folder.url,
                toFolder: folder.url
            )
            deleted = store.deletePermanently(folder)
            if deleted {
                for pair in pairs {
                    EditorPositionStore.shared.removePosition(for: pair.sourceURL)
                    libraryMetadata.removeMetadata(for: pair.sourceURL)
                }
            }
        }
        guard deleted else {
            pendingPermanentDeletion = nil
            return
        }
        rebuildDeletedItems()
        pendingPermanentDeletion = nil

        announceSuccess("\(item.displayName) deleted permanently")
    }

    private func emptyRecentlyDeleted() {
        let items = deletedItems

        for item in items {
            switch item.item {
            case .document(let document):
                guard store.deletePermanently(document) else {
                    rebuildDeletedItems()
                    return
                }
                EditorPositionStore.shared.removePosition(for: document.url)
                libraryMetadata.removeMetadata(for: document.url)
            case .folder(let folder):
                let pairs = store.documentMovePairs(
                    fromFolder: folder.url,
                    toFolder: folder.url
                )
                guard store.deletePermanently(folder) else {
                    rebuildDeletedItems()
                    return
                }
                for pair in pairs {
                    EditorPositionStore.shared.removePosition(for: pair.sourceURL)
                    libraryMetadata.removeMetadata(for: pair.sourceURL)
                }
            }
        }

        rebuildDeletedItems()
    }

    private func dismissError() {
        store.lastError = nil
    }

    private func announceSuccess(_ message: String) {
        statusMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)

        Task {
            try? await Task.sleep(for: .seconds(4))
            if statusMessage == message {
                statusMessage = ""
            }
        }
    }

    private func migrateFolderMetadata(
        _ pairs: [DocumentMigrationPair],
        fromRoot: URL,
        toRoot: URL
    ) {
        for pair in pairs {
            let relativeComponents = pair.sourceURL.pathComponents
                .dropFirst(fromRoot.pathComponents.count)
            let destinationURL = relativeComponents.reduce(toRoot) {
                $0.appendingPathComponent($1)
            }
            EditorPositionStore.shared.migratePosition(
                from: pair.sourceURL,
                to: destinationURL
            )
            libraryMetadata.migrateMetadata(
                from: pair.sourceURL,
                to: destinationURL
            )
        }
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

/// One deleted item, collapsed into a single element reading as one sentence
/// rather than a name and a kind announced as disconnected fragments.
private struct DeletedItemRow: View {
    let item: DeletedLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName)
                .font(.headline)
                .foregroundStyle(Color.ghostText)

            Label(
                item.isFolder ? "Folder" : "Document",
                systemImage: item.isFolder ? "folder" : "doc.text"
            )
            .font(.caption)
            .foregroundStyle(Color.ghostMuted)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.displayName), deleted \(item.isFolder ? "folder" : "document")"
        )
        .accessibilityHint("Restores this item")
    }
}
