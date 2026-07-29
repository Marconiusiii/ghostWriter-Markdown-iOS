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
    }

    func togglePin(for url: URL) {
        let documentKey = key(for: url)
        if pinnedKeys.contains(documentKey) {
            pinnedKeys.remove(documentKey)
        } else {
            pinnedKeys.insert(documentKey)
        }
    }

    func recordOpened(_ url: URL, at date: Date = .now) {
        lastOpenedTimestamps[key(for: url)] = date.timeIntervalSince1970
    }

    func lastOpened(_ url: URL) -> Date? {
        lastOpenedTimestamps[key(for: url)].map {
            Date(timeIntervalSince1970: $0)
        }
    }

    func migrateMetadata(from oldURL: URL, to newURL: URL) {
        let oldKey = key(for: oldURL)
        let newKey = key(for: newURL)
        guard oldKey != newKey else { return }

        if pinnedKeys.remove(oldKey) != nil {
            pinnedKeys.insert(newKey)
        }

        if let oldTimestamp = lastOpenedTimestamps.removeValue(forKey: oldKey) {
            lastOpenedTimestamps[newKey] = max(
                oldTimestamp,
                lastOpenedTimestamps[newKey] ?? oldTimestamp
            )
        }
    }

    func removeMetadata(for url: URL) {
        let documentKey = key(for: url)
        pinnedKeys.remove(documentKey)
        lastOpenedTimestamps.removeValue(forKey: documentKey)
    }

    private func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
