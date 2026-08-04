import Foundation

nonisolated struct LibraryFolder: Identifiable, Hashable, Sendable {
    let url: URL
    let created: Date
    let modified: Date

    var id: URL { url }
    var displayName: String { url.lastPathComponent }

    init(url: URL, created: Date = .distantPast, modified: Date = .distantPast) {
        self.url = url.standardizedFileURL
        self.created = created
        self.modified = modified
    }

    init?(fileURL: URL) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isDirectory == true,
              !fileURL.lastPathComponent.hasPrefix(".") else {
            return nil
        }
        self.init(
            url: fileURL,
            created: values.creationDate ?? .distantPast,
            modified: values.contentModificationDate
                ?? values.creationDate
                ?? .distantPast
        )
    }
}

nonisolated enum LibraryItem: Identifiable, Hashable, Sendable {
    case folder(LibraryFolder)
    case document(Document)

    var id: URL { url }
    var url: URL {
        switch self {
        case .folder(let folder): folder.url
        case .document(let document): document.url
        }
    }
    var displayName: String {
        switch self {
        case .folder(let folder): folder.displayName
        case .document(let document): document.displayName
        }
    }
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}
