import Foundation

/// Inclusion and order are local to an export. Excluding a parent never rewrites
/// descendants' choices, so including that folder again restores those choices.
nonisolated struct CompilationItem: Identifiable, Equatable, Sendable {
    let item: LibraryItem
    var isIncluded = true
    var children: [CompilationItem] = []

    var id: URL { item.id }

    var includedDocuments: [Document] {
        guard isIncluded else { return [] }
        switch item {
        case .document(let document): return [document]
        case .folder: return children.flatMap(\.includedDocuments)
        }
    }

    var hasReorderableContents: Bool {
        children.count > 1 || children.contains(where: \.hasReorderableContents)
    }
}

extension CompilationSelection {
    static func folder(
        at directory: URL,
        documents: [Document],
        folders: [LibraryFolder],
        metadata: DocumentLibraryMetadataStore
    ) -> CompilationItem {
        let parent = directory.standardizedFileURL
        let children = documents.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL.path == parent.path
        }.map(LibraryItem.document) + folders.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL.path == parent.path
        }.map(LibraryItem.folder)
        let byURL = Dictionary(uniqueKeysWithValues: children.map { ($0.url, $0) })
        let ordered = metadata.manuallyOrdered(children.map(\.url)).compactMap { url -> CompilationItem? in
            guard let item = byURL[url] else { return nil }
            switch item {
            case .document: return CompilationItem(item: item)
            case .folder:
                return folder(at: url, documents: documents, folders: folders, metadata: metadata)
            }
        }
        return CompilationItem(item: .folder(LibraryFolder(url: directory)), children: ordered)
    }
}
