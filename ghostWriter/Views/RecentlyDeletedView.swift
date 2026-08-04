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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var pendingPermanentDeletion: DeletedLibraryItem?
    @State private var showingEmptyConfirmation = false
    @State private var focusAfterError: FocusTarget?
    @State private var focusRequestGate = FocusRestorationRequestGate()
    @State private var statusMessage = ""
    @AccessibilityFocusState private var focusedElement: FocusTarget?

    private enum FocusTarget: Hashable {
        case count
        case item(URL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text("Recently Deleted")
                    .font(.title.bold())
                    .foregroundStyle(Color.ghostAccent)
                    .accessibilityAddTraits(.isHeader)

                Button("Back") { dismiss() }
                    .buttonStyle(.bordered)

                Text(countDescription)
                    .font(.title3.bold())
                    .foregroundStyle(Color.ghostAccent)
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .count
                    )

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
                    focusRequestGate.invalidate()
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
        .onAppear { store.refresh() }
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
            Button("Cancel", role: .cancel) {
                restoreFocus(to: .count)
            }
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
                deletedDocumentLayout {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.ghostText)
                        Text(item.isFolder ? "Folder" : "Document")
                            .font(.caption)
                            .foregroundStyle(Color.ghostMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(item.displayName), \(item.isFolder ? "folder" : "document")"
                    )
                    .accessibilityHint("Deleted item")
                    .accessibilityAction(
                        named: "Restore \(item.displayName)"
                    ) {
                        restore(item)
                    }
                    .accessibilityAction(
                        named: "Delete \(item.displayName) Permanently"
                    ) {
                        beginPermanentDeletion(item)
                    }
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .item(item.url)
                    )

                    RecentlyDeletedActionsMenu(
                        item: item,
                        onRestore: { restore(item) },
                        onDeletePermanently: {
                            beginPermanentDeletion(item)
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

    private var deletedDocumentLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        }
        return AnyLayout(HStackLayout(spacing: 8))
    }

    private var deletedItems: [DeletedLibraryItem] {
        store.recentlyDeletedItems.sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
    }

    private var countDescription: String {
        let count = deletedItems.count
        return "\(count) \(count == 1 ? "deleted item" : "deleted items")"
    }

    private func restore(_ item: DeletedLibraryItem) {
        focusRequestGate.invalidate()
        let nextTarget = focusAfterRemoving(item)
        focusAfterError = .item(item.url)

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
        focusAfterError = nil
        announceSuccess("\(item.displayName) restored")
        restoreFocus(to: availableFocus(nextTarget))
    }

    private func beginPermanentDeletion(_ item: DeletedLibraryItem) {
        focusRequestGate.invalidate()
        pendingPermanentDeletion = item
    }

    private func cancelPermanentDeletion() {
        guard let item = pendingPermanentDeletion else { return }
        pendingPermanentDeletion = nil
        restoreFocus(to: availableFocus(.item(item.url)))
    }

    private func commitPermanentDeletion() {
        guard let item = pendingPermanentDeletion else { return }
        let nextTarget = focusAfterRemoving(item)
        focusAfterError = .item(item.url)

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
        pendingPermanentDeletion = nil
        focusAfterError = nil
        announceSuccess("\(item.displayName) deleted permanently")
        restoreFocus(to: availableFocus(nextTarget))
    }

    private func emptyRecentlyDeleted() {
        focusRequestGate.invalidate()
        let items = deletedItems
        focusAfterError = .count

        for item in items {
            switch item.item {
            case .document(let document):
                guard store.deletePermanently(document) else { return }
                EditorPositionStore.shared.removePosition(for: document.url)
                libraryMetadata.removeMetadata(for: document.url)
            case .folder(let folder):
                let pairs = store.documentMovePairs(
                    fromFolder: folder.url,
                    toFolder: folder.url
                )
                guard store.deletePermanently(folder) else { return }
                for pair in pairs {
                    EditorPositionStore.shared.removePosition(for: pair.sourceURL)
                    libraryMetadata.removeMetadata(for: pair.sourceURL)
                }
            }
        }

        focusAfterError = nil
        restoreFocus(to: .count)
    }

    private func focusAfterRemoving(_ item: DeletedLibraryItem) -> FocusTarget {
        guard let index = deletedItems.firstIndex(of: item) else {
            return .count
        }
        if index + 1 < deletedItems.count {
            return .item(deletedItems[index + 1].url)
        }
        if index > 0 {
            return .item(deletedItems[index - 1].url)
        }
        return .count
    }

    private func availableFocus(_ target: FocusTarget) -> FocusTarget {
        if case .item(let url) = target,
           !deletedItems.contains(where: { $0.url == url }) {
            return .count
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
        let target = availableFocus(focusAfterError ?? .count)
        focusAfterError = nil
        restoreFocus(to: target)
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

private struct RecentlyDeletedActionsMenu: View {
    let item: DeletedLibraryItem
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    var body: some View {
        Menu {
            Button(action: onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .accessibilityLabel("Restore \(item.displayName)")

            Button(role: .destructive, action: onDeletePermanently) {
                Label(
                    "Delete \(item.displayName) Permanently",
                    systemImage: "trash.slash"
                )
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Actions for \(item.displayName)")
    }
}
