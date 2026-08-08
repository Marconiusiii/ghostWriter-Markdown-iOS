import Foundation

nonisolated struct DeletedLibraryItem: Identifiable, Hashable, Sendable {
    let item: LibraryItem
    let originalRelativePath: String?

    var id: URL { item.id }
    var url: URL { item.url }
    var displayName: String { item.displayName }
    var isFolder: Bool { item.isFolder }
}

nonisolated struct DeletedItemRecord: Codable, Equatable, Sendable {
    let originalRelativePath: String
}
