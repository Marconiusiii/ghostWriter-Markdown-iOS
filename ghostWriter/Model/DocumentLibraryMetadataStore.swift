//
//  DocumentLibraryMetadataStore.swift
//  ghostWriter
//
//  Library-only metadata that must never be written into a writer's Markdown
//  file: pinned state and the last time a document entered the editor.
//

import Foundation
import Observation

@Observable
final class DocumentLibraryMetadataStore {
    private(set) var pinnedKeys: Set<String> {
        didSet {
            defaults.set(Array(pinnedKeys).sorted(), forKey: pinnedStorageKey)
        }
    }

    private(set) var lastOpenedTimestamps: [String: TimeInterval] {
        didSet {
            defaults.set(lastOpenedTimestamps, forKey: lastOpenedStorageKey)
        }
    }

    private let defaults: UserDefaults
    private let pinnedStorageKey: String
    private let lastOpenedStorageKey: String

    init(
        defaults: UserDefaults = .standard,
        pinnedStorageKey: String = "pinnedDocuments",
        lastOpenedStorageKey: String = "documentLastOpened"
    ) {
        self.defaults = defaults
        self.pinnedStorageKey = pinnedStorageKey
        self.lastOpenedStorageKey = lastOpenedStorageKey
        self.pinnedKeys = Set(
            defaults.stringArray(forKey: pinnedStorageKey) ?? []
        )
        self.lastOpenedTimestamps = defaults
            .dictionary(forKey: lastOpenedStorageKey)?
            .reduce(into: [:]) { result, item in
                if let number = item.value as? NSNumber {
                    result[item.key] = number.doubleValue
                }
            } ?? [:]
    }

    func isPinned(_ url: URL) -> Bool {
        pinnedKeys.contains(key(for: url))
            || pinnedKeys.contains(legacyKey(for: url))
    }

    func togglePin(for url: URL) {
        let documentKey = key(for: url)
        let legacyDocumentKey = legacyKey(for: url)
        if pinnedKeys.contains(documentKey)
            || pinnedKeys.contains(legacyDocumentKey) {
            pinnedKeys.remove(documentKey)
            pinnedKeys.remove(legacyDocumentKey)
        } else {
            pinnedKeys.insert(documentKey)
        }
    }

    func recordOpened(_ url: URL, at date: Date = .now) {
        lastOpenedTimestamps[key(for: url)] = date.timeIntervalSince1970
    }

    func lastOpened(_ url: URL) -> Date? {
        (
            lastOpenedTimestamps[key(for: url)]
                ?? lastOpenedTimestamps[legacyKey(for: url)]
        ).map {
            Date(timeIntervalSince1970: $0)
        }
    }

    func mostRecentlyOpenedDocument(in documents: [Document]) -> Document? {
        documents.compactMap { document -> (Document, Date)? in
            guard let date = lastOpened(document.url) else { return nil }
            return (document, date)
        }
        .max { left, right in
            left.1 < right.1
        }?.0
    }

    func migrateMetadata(from oldURL: URL, to newURL: URL) {
        let oldKey = key(for: oldURL)
        let newKey = key(for: newURL)
        let oldLegacyKey = legacyKey(for: oldURL)

        let removedStablePin = pinnedKeys.remove(oldKey)
        let removedLegacyPin = pinnedKeys.remove(oldLegacyKey)
        if removedStablePin != nil || removedLegacyPin != nil {
            pinnedKeys.insert(newKey)
        }

        let stableTimestamp = lastOpenedTimestamps.removeValue(forKey: oldKey)
        let legacyTimestamp = lastOpenedTimestamps.removeValue(
            forKey: oldLegacyKey
        )
        let oldTimestamp = max(
            stableTimestamp ?? -.infinity,
            legacyTimestamp ?? -.infinity
        )
        if oldTimestamp.isFinite {
            lastOpenedTimestamps[newKey] = max(
                oldTimestamp,
                lastOpenedTimestamps[newKey] ?? oldTimestamp
            )
        }
    }

    func removeMetadata(for url: URL) {
        let documentKey = key(for: url)
        pinnedKeys.remove(documentKey)
        pinnedKeys.remove(legacyKey(for: url))
        lastOpenedTimestamps.removeValue(forKey: documentKey)
        lastOpenedTimestamps.removeValue(forKey: legacyKey(for: url))
    }

    private func key(for url: URL) -> String {
        DocumentStorageKey.key(for: url)
    }

    private func legacyKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
