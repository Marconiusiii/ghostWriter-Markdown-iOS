//
//  DocumentLibraryMetadataStore.swift
//  ghostWriter
//
//  Library-only metadata that must never be written into a writer's Markdown
//  file: pinned state, last-opened time, and export language.
//

import Foundation
import Observation

@Observable
final class DocumentLibraryMetadataStore {
    private(set) var libraryPresentationRevision = 0
    private(set) var libraryRoot: URL?
    private(set) var pinnedKeys: Set<String> {
        didSet {
            defaults.set(Array(pinnedKeys).sorted(), forKey: pinnedStorageKey)
            libraryPresentationRevision &+= 1
        }
    }

    private(set) var lastOpenedTimestamps: [String: TimeInterval] {
        didSet {
            defaults.set(lastOpenedTimestamps, forKey: lastOpenedStorageKey)
            libraryPresentationRevision &+= 1
        }
    }

    private(set) var documentLanguageTags: [String: String] {
        didSet {
            defaults.set(documentLanguageTags, forKey: languageStorageKey)
            libraryPresentationRevision &+= 1
        }
    }

    private let defaults: UserDefaults
    private let pinnedStorageKey: String
    private let lastOpenedStorageKey: String
    private let languageStorageKey: String

    init(
        defaults: UserDefaults = .standard,
        pinnedStorageKey: String = "pinnedDocuments",
        lastOpenedStorageKey: String = "documentLastOpened",
        languageStorageKey: String = "documentLanguageTags"
    ) {
        self.defaults = defaults
        self.pinnedStorageKey = pinnedStorageKey
        self.lastOpenedStorageKey = lastOpenedStorageKey
        self.languageStorageKey = languageStorageKey
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
        self.documentLanguageTags = defaults.dictionary(forKey: languageStorageKey) as? [String: String] ?? [:]
    }

    func useLibraryRoot(_ root: URL?) {
        let standardizedRoot = root?.standardizedFileURL
        guard libraryRoot != standardizedRoot else { return }
        libraryRoot = standardizedRoot
        libraryPresentationRevision &+= 1
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

    func documentLanguage(for url: URL) -> String {
        documentLanguageTags[key(for: url)]
            ?? documentLanguageTags[legacyKey(for: url)]
            ?? DocumentLanguage.automatic
    }

    func setDocumentLanguage(_ tag: String, for url: URL) {
        let documentKey = key(for: url)
        documentLanguageTags.removeValue(forKey: legacyKey(for: url))
        let normalized = DocumentLanguage.normalizedTag(tag)
        if normalized.isEmpty {
            documentLanguageTags.removeValue(forKey: documentKey)
        } else {
            documentLanguageTags[documentKey] = normalized
        }
    }

    func copyMetadata(from sourceURL: URL, to destinationURL: URL) {
        if isPinned(sourceURL) { pinnedKeys.insert(key(for: destinationURL)) }
        if let opened = lastOpened(sourceURL) {
            lastOpenedTimestamps[key(for: destinationURL)] = opened.timeIntervalSince1970
        }
        let language = documentLanguage(for: sourceURL)
        if !language.isEmpty {
            documentLanguageTags[key(for: destinationURL)] = language
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
        migrateMetadata(
            from: oldURL,
            relativeTo: libraryRoot,
            to: newURL,
            relativeTo: libraryRoot
        )
    }

    func migrateMetadata(
        from oldURL: URL,
        relativeTo oldRoot: URL?,
        to newURL: URL,
        relativeTo newRoot: URL?
    ) {
        let oldKey = key(for: oldURL, relativeTo: oldRoot)
        let newKey = key(for: newURL, relativeTo: newRoot)
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


        let stableLanguage = documentLanguageTags.removeValue(forKey: oldKey)
        let legacyLanguage = documentLanguageTags.removeValue(forKey: oldLegacyKey)
        if let language = stableLanguage ?? legacyLanguage {
            documentLanguageTags[newKey] = language
        }
    }

    func removeMetadata(for url: URL) {
        let documentKey = key(for: url)
        pinnedKeys.remove(documentKey)
        pinnedKeys.remove(legacyKey(for: url))
        lastOpenedTimestamps.removeValue(forKey: documentKey)
        lastOpenedTimestamps.removeValue(forKey: legacyKey(for: url))
        documentLanguageTags.removeValue(forKey: documentKey)
        documentLanguageTags.removeValue(forKey: legacyKey(for: url))
    }

    private func key(for url: URL) -> String {
        key(for: url, relativeTo: libraryRoot)
    }

    private func key(for url: URL, relativeTo root: URL?) -> String {
        root.map { DocumentStorageKey.key(for: url, relativeTo: $0) }
            ?? DocumentStorageKey.key(for: url)
    }

    private func legacyKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
