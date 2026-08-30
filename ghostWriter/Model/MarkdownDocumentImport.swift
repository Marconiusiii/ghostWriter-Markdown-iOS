import Foundation

/// A completed conversion, before its document and attachments are placed.
nonisolated struct MarkdownDocumentImport: Equatable, Sendable {
    var markdown: String
    var assets: [MarkdownImportedAsset]
    var imagesNeedingAlternativeText: Int
    var assetDirectoryName: String?
    var notices: [String] = []
}

nonisolated struct MarkdownImportedAsset: Equatable, Sendable {
    var fileName: String
    var data: Data
}
