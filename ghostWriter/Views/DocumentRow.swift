//
//  DocumentRow.swift
//  ghostWriter
//
//  One file in the library. LibraryView places this content inside a native NavigationLink
//  that opens the editor and carries the document's accessibility actions.
//
//  The accessibility label is written as a single sentence rather than letting
//  three separate Text views be read as disconnected fragments. Hearing
//  "Meeting notes, modified yesterday, created 3 March" is far better than
//  "Meeting notes" then "yesterday" then "3 March" with no idea which is which.
//

import SwiftUI

struct FileListVerbosity: Equatable {
    var creationDates = true
    var modifiedDates = true
    var compilationStatus = true
}

enum LibraryCompilationStatus: Equatable {
    case included, excluded

    var label: String {
        self == .included ? String(localized: "Included in Compilations") : String(localized: "Excluded from Compilations")
    }

    var symbol: String {
        self == .included ? "checkmark.circle" : "minus.circle"
    }
}

struct LibraryDocumentPresentation: Identifiable, Equatable {
    let document: Document
    let isPinned: Bool
    let verbosity: FileListVerbosity
    let compilationStatus: LibraryCompilationStatus?
    let modifiedDescription: String
    let createdDescription: String
    let accessibilityLabel: String
    let accessibilityHint: String

    var id: URL { document.url }

    init(document: Document, isPinned: Bool, verbosity: FileListVerbosity = .init(), included: Bool = true) {
        self.verbosity = verbosity
        self.compilationStatus = verbosity.compilationStatus ? (included ? .included : .excluded) : nil
        self.document = document
        self.isPinned = isPinned
        self.modifiedDescription = DateFormatting.short(document.modified)
        self.createdDescription = DateFormatting.short(document.created)

        let pinDescription = isPinned ? "Pinned, " : ""
        let statusDescription = document.availability.statusDescription
            .map { ", \($0)" } ?? ""
        var label = "\(pinDescription)\(document.displayName)"
        if verbosity.modifiedDates { label += ", modified \(DateFormatting.spoken(document.modified))" }
        if verbosity.creationDates { label += ", created \(DateFormatting.spoken(document.created))" }
        if let compilationStatus { label += ", \(compilationStatus.label)" }
        self.accessibilityLabel = label + statusDescription
        self.accessibilityHint = document.availability.isAvailable
            ? "Opens in the editor"
            : "Downloads this document and opens it when ready"
    }
}

struct LibraryFolderPresentation: Identifiable, Equatable {
    let folder: LibraryFolder
    let itemCount: Int
    var compilationStatus: LibraryCompilationStatus? = nil

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
        metadata: DocumentLibraryMetadataStore,
        verbosity: FileListVerbosity = .init()
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
                isPinned: metadata.isPinned(document.url),
                verbosity: verbosity,
                included: metadata.isIncludedByDefault(document.url)
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
                    + folderCounts[folder.url.standardizedFileURL, default: 0],
                compilationStatus: verbosity.compilationStatus
                    ? (metadata.isIncludedByDefault(folder.url) ? .included : .excluded) : nil
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
                if presentation.verbosity.modifiedDates {
                    Label(presentation.modifiedDescription, systemImage: "pencil")
                }
                if presentation.verbosity.creationDates {
                    Label(presentation.createdDescription, systemImage: "calendar")
                }
                if let status = presentation.compilationStatus {
                    Image(systemName: status.symbol)
                        .accessibilityHidden(true)
                }
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
        // LibraryView supplies the label and hint on the native NavigationLink.
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
