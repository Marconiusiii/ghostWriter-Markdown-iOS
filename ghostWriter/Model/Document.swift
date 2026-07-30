//
//  Document.swift
//  ghostWriter
//
//  A single markdown file on disk. This is a value type describing the file's
//  identity and metadata; the text itself is loaded on demand by DocumentStore
//  so that listing the library never has to read every file's contents.
//

import Foundation

// The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
// would otherwise pin this type to the main actor. Document is a plain value
// type describing a file — it touches no UI — so it is marked nonisolated and
// can be constructed from any context, including background file scans.
nonisolated struct Document: Identifiable, Hashable {
    /// The file URL is the identity. Two Document values pointing at the same
    /// path are the same document, which is what lets SwiftUI diff the list
    /// correctly when files are renamed or re-sorted.
    let url: URL
    let created: Date
    let modified: Date
    /// Size in bytes, used for the accessibility description of a row.
    let byteCount: Int
    let availability: DocumentAvailability

    var id: URL { url }

    /// The name shown to the user, without the `.md` extension. The extension
    /// is an implementation detail of storage, not something a writer should
    /// have to hear announced on every row.
    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var fileName: String {
        url.lastPathComponent
    }

    init(
        url: URL,
        created: Date,
        modified: Date,
        byteCount: Int,
        availability: DocumentAvailability = .available
    ) {
        self.url = url
        self.created = created
        self.modified = modified
        self.byteCount = byteCount
        self.availability = availability
    }
}

nonisolated extension Document {
    /// Builds a Document by reading the filesystem's own metadata. Returns nil
    /// for anything that is not a readable markdown file, so callers can map
    /// over a directory listing and discard non-documents in one pass.
    init?(fileURL: URL) {
        guard Document.isMarkdown(fileURL) else { return nil }

        let keys: Set<URLResourceKey> = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadingErrorKey
        ]

        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isRegularFile == true else {
            return nil
        }

        let availability: DocumentAvailability
        if values.isUbiquitousItem == true {
            availability = DocumentAvailability.iCloudState(
                downloadingStatus: values.ubiquitousItemDownloadingStatus?.rawValue,
                isDownloading: values.ubiquitousItemIsDownloading ?? false,
                percentDownloaded: nil,
                errorDescription: values.ubiquitousItemDownloadingError?
                    .localizedDescription
            )
        } else {
            availability = .available
        }

        // A missing timestamp is possible on some filesystems. Falling back to
        // the distant past keeps sorting total rather than crashing.
        self.init(
            url: fileURL,
            created: values.creationDate ?? .distantPast,
            modified: values.contentModificationDate
                ?? values.creationDate
                ?? .distantPast,
            byteCount: values.fileSize ?? 0,
            availability: availability
        )
    }

    /// Recognised markdown extensions. `.markdown` and `.txt` are accepted so
    /// files imported through the Files app are not invisible to the library.
    static let readableExtensions: Set<String> = ["md", "markdown", "mdown", "txt"]

    static func isMarkdown(_ url: URL) -> Bool {
        readableExtensions.contains(url.pathExtension.lowercased())
    }
}
