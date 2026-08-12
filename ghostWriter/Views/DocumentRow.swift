//
//  DocumentRow.swift
//  ghostWriter
//
//  One file in the library. The row is a navigation link that opens the editor,
//  and carries custom accessibility actions for rendering and sharing.
//
//  The accessibility label is written as a single sentence rather than letting
//  three separate Text views be read as disconnected fragments. Hearing
//  "Meeting notes, modified yesterday, created 3 March" is far better than
//  "Meeting notes" then "yesterday" then "3 March" with no idea which is which.
//

import SwiftUI

struct LibraryDocumentPresentation: Identifiable, Equatable {
    let document: Document
    let isPinned: Bool
    let modifiedDescription: String
    let createdDescription: String
    let accessibilityLabel: String
    let accessibilityHint: String

    var id: URL { document.url }

    init(document: Document, isPinned: Bool) {
        self.document = document
        self.isPinned = isPinned
        self.modifiedDescription = DateFormatting.short(document.modified)
        self.createdDescription = DateFormatting.short(document.created)

        let pinDescription = isPinned ? "Pinned, " : ""
        let statusDescription = document.availability.statusDescription
            .map { ", \($0)" } ?? ""
        self.accessibilityLabel = "\(pinDescription)\(document.displayName), modified \(DateFormatting.spoken(document.modified)), created \(DateFormatting.spoken(document.created))\(statusDescription)"
        self.accessibilityHint = document.availability.isAvailable
            ? "Opens in the editor"
            : "Downloads this document and opens it when ready"
    }
}

struct LibraryFolderPresentation: Identifiable, Equatable {
    let folder: LibraryFolder
    let itemCount: Int

    var id: URL { folder.url }
}

struct LibraryPresentationSnapshot: Equatable {
    static let empty = LibraryPresentationSnapshot(
        documents: [],
        folders: [],
        currentItemCount: 0
    )

    let documents: [LibraryDocumentPresentation]
    let folders: [LibraryFolderPresentation]
    let currentItemCount: Int

    static func build(
        documents: [Document],
        folders: [LibraryFolder],
        currentDirectory: URL,
        query: String,
        searchIndex: DocumentSearchIndex,
        sort: DocumentSort,
        metadata: DocumentLibraryMetadataStore
    ) -> LibraryPresentationSnapshot {
        let standardizedDirectory = currentDirectory.standardizedFileURL
        let currentDocuments = documents.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL
                == standardizedDirectory
        }
        let currentFolders = folders.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL
                == standardizedDirectory
        }

        let filteredDocuments: [Document]
        if query.isEmpty {
            filteredDocuments = currentDocuments
        } else {
            filteredDocuments = currentDocuments.filter { document in
                searchIndex.matches(
                    documentURL: document.url,
                    displayName: document.displayName,
                    query: query
                )
            }
        }

        let documentRows = sort.sorted(
            filteredDocuments,
            metadata: metadata
        ).map { document in
            LibraryDocumentPresentation(
                document: document,
                isPinned: metadata.isPinned(document.url)
            )
        }

        let visibleFolders = currentFolders.filter {
            query.isEmpty
                || $0.displayName.localizedCaseInsensitiveContains(query)
        }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
        let documentCounts = Dictionary(grouping: documents) {
            $0.url.deletingLastPathComponent().standardizedFileURL
        }.mapValues(\.count)
        let folderCounts = Dictionary(grouping: folders) {
            $0.url.deletingLastPathComponent().standardizedFileURL
        }.mapValues(\.count)
        let folderRows = visibleFolders.map { folder in
            LibraryFolderPresentation(
                folder: folder,
                itemCount: documentCounts[folder.url.standardizedFileURL, default: 0]
                    + folderCounts[folder.url.standardizedFileURL, default: 0]
            )
        }

        return LibraryPresentationSnapshot(
            documents: documentRows,
            folders: folderRows,
            currentItemCount: currentDocuments.count + currentFolders.count
        )
    }
}

struct DocumentRow: View {
    let presentation: LibraryDocumentPresentation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLayout {
                Text(presentation.document.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.ghostText)

                if presentation.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Color.ghostAccent)
                }
            }

            metadataLayout {
                Label(presentation.modifiedDescription, systemImage: "pencil")
                Label(presentation.createdDescription, systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(Color.ghostMuted)
            .labelStyle(.titleAndIcon)

            if let status = presentation.document.availability.statusDescription {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Color.ghostMuted)
            }
        }
        .padding(.vertical, 4)
        // Collapse the row into one element with one coherent sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.accessibilityHint)
    }

    private var metadataLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 12))
    }

    private var titleLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 8))
    }
}

/// A visible, discoverable counterpart to swipe and custom accessibility
/// actions. It remains in the accessibility hierarchy for Switch Control,
/// Voice Control, keyboard navigation, and VoiceOver. Every accessible name
/// starts with its visible label and ends with the document name.
struct DocumentActionsMenu: View {
    let document: Document
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onRender: () -> Void
    let onShare: () -> Void
    let onRename: () -> Void
    let onMove: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            actionButton(
                isPinned ? "Unpin" : "Pin",
                systemImage: isPinned ? "pin.slash" : "pin",
                action: onTogglePin
            )

            Divider()

            actionButton(
                "Render",
                systemImage: "doc.richtext",
                action: onRender
            )
            actionButton(
                "Share",
                systemImage: "square.and.arrow.up",
                action: onShare
            )
            actionButton(
                "Rename",
                systemImage: "pencil",
                action: onRename
            )
            actionButton(
                "Move",
                systemImage: "folder",
                action: onMove
            )
            actionButton(
                "Duplicate",
                systemImage: "doc.on.doc",
                action: onDuplicate
            )
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete \(document.displayName)")
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Actions for \(document.displayName)")
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .accessibilityLabel("\(title) \(document.displayName)")
    }
}
