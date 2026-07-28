//
//  DocumentSearchIndex.swift
//  ghostWriter
//
//  A read-only snapshot of document text used by Library search. Building it
//  is deliberately independent of SwiftUI and DocumentStore so file reads can
//  happen away from the main interface thread.
//

import Foundation

nonisolated struct DocumentSearchSource: Sendable, Equatable {
    let url: URL
    let displayName: String
    let modified: Date
    let byteCount: Int
}

nonisolated struct DocumentSearchIndex: Sendable, Equatable {
    private struct Entry: Sendable, Equatable {
        let displayName: String
        let contents: String?
    }

    static let empty = DocumentSearchIndex(entries: [:])

    private let entries: [URL: Entry]

    static func build(from sources: [DocumentSearchSource]) -> DocumentSearchIndex {
        var entries: [URL: Entry] = [:]
        entries.reserveCapacity(sources.count)

        for source in sources {
            guard !Task.isCancelled else { break }
            entries[source.url] = Entry(
                displayName: source.displayName,
                contents: try? String(contentsOf: source.url, encoding: .utf8)
            )
        }

        return DocumentSearchIndex(entries: entries)
    }

    func matches(documentURL: URL, displayName: String, query: String) -> Bool {
        if displayName.localizedCaseInsensitiveContains(query) {
            return true
        }

        guard let entry = entries[documentURL] else { return false }
        return entry.displayName.localizedCaseInsensitiveContains(query)
            || entry.contents?.localizedCaseInsensitiveContains(query) == true
    }
}
