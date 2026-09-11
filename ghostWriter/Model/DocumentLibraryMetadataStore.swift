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
    private(set) var excludedCompilationKeys: Set<String> {
        didSet {
            defaults.set(Array(excludedCompilationKeys).sorted(), forKey: "excludedCompilationItems")
            libraryPresentationRevision &+= 1
        }
    }

    func isIncludedByDefault(_ url: URL) -> Bool { !excludedCompilationKeys.contains(manualKey(for: url)) }
    func inclusionActionLabel(for url: URL) -> String {
        isIncludedByDefault(url) ? String(localized: "Exclude from Compilations") : String(localized: "Include in Compilations")
    }
    @discardableResult
    func toggleDefaultInclusion(for url: URL) -> String {
        let key = manualKey(for: url)
        if !excludedCompilationKeys.insert(key).inserted { excludedCompilationKeys.remove(key) }
        let format = isIncludedByDefault(url)
            ? String(localized: "%@ included")
            : String(localized: "%@ excluded")
        return String(format: format, url.lastPathComponent)
    }

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

    private(set) var manualOrders: [String: [String]] {
        didSet {
            defaults.set(manualOrders, forKey: "libraryManualOrders")
            libraryPresentationRevision &+= 1
        }
    }

    private(set) var folderSortPreferences: [String: [String: String]] {
        didSet {
            defaults.set(folderSortPreferences, forKey: "libraryFolderSortPreferences")
            libraryPresentationRevision &+= 1
        }
    }

    func sort(in directory: URL, fallback: DocumentSort) -> DocumentSort {
        guard let saved = folderSortPreferences[manualKey(for: directory)],
              let rawField = saved["field"], let field = DocumentSortField(rawValue: rawField),
              let rawDirection = saved["direction"], let direction = SortDirection(rawValue: rawDirection)
        else { return fallback }
        return DocumentSort(field: field, direction: direction)
    }

    func setSort(_ sort: DocumentSort, in directory: URL) {
        folderSortPreferences[manualKey(for: directory)] = [
            "field": sort.field.rawValue, "direction": sort.direction.rawValue
        ]
    }

    /// Missing items append alphabetically. Filtering never rewrites the saved order.
    func manuallyOrdered(_ urls: [URL]) -> [URL] {
        guard let parent = urls.first?.deletingLastPathComponent() else { return [] }
        let order = manualOrders[manualKey(for: parent)] ?? []
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return urls.sorted {
            let left = ranks[manualKey(for: $0)] ?? Int.max
            let right = ranks[manualKey(for: $1)] ?? Int.max
            if left != right { return left < right }
            let comparison = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
    }

    func setManualOrder(_ urls: [URL], in directory: URL) {
        var seen: Set<String> = []
        manualOrders[manualKey(for: directory)] = urls.filter {
            $0.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
        }.map { manualKey(for: $0) }.filter { seen.insert($0).inserted }
    }

    /// Folder renames also update descendant order keys. Cross-folder moves append.
    func migrateManualOrder(from oldURL: URL, to newURL: URL) {
        let old = manualKey(for: oldURL)
        let new = manualKey(for: newURL)
        guard old != new else { return }
        let sameParent = oldURL.deletingLastPathComponent().standardizedFileURL.path == newURL.deletingLastPathComponent().standardizedFileURL.path
        func replacingRoot(_ value: String) -> String {
            if value == old { return new }
            if value.hasPrefix(old + "/") { return new + value.dropFirst(old.count) }
            return value
        }
        var updated: [String: [String]] = [:]
        for (directory, items) in manualOrders {
            updated[replacingRoot(directory)] = items.compactMap { item in
                if item == old && !sameParent { return nil }
                return replacingRoot(item)
            }
        }
        if !sameParent {
            let parent = manualKey(for: newURL.deletingLastPathComponent())
            if let siblings = updated[parent], !siblings.contains(new) { updated[parent, default: []].append(new) }
        }
        excludedCompilationKeys = Set(excludedCompilationKeys.map(replacingRoot))
        manualOrders = updated
        var migratedSorts: [String: [String: String]] = [:]
        for (directory, sort) in folderSortPreferences {
            migratedSorts[replacingRoot(directory)] = sort
        }
        folderSortPreferences = migratedSorts
    }

    func removeFolderPreferences(at directory: URL) {
        let root = manualKey(for: directory)
        func belongsToFolder(_ key: String) -> Bool {
            key == root || key.hasPrefix(root + "/")
        }
        excludedCompilationKeys = excludedCompilationKeys.filter { !belongsToFolder($0) }
        folderSortPreferences = folderSortPreferences.filter { !belongsToFolder($0.key) }
        manualOrders = manualOrders.filter { !belongsToFolder($0.key) }.mapValues {
            $0.filter { !belongsToFolder($0) }
        }
    }

    private func manualKey(for url: URL) -> String {
        if url.standardizedFileURL.path == libraryRoot?.path { return "." }
        return key(for: url)
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
        self.excludedCompilationKeys = Set(defaults.stringArray(forKey: "excludedCompilationItems") ?? [])
        self.folderSortPreferences = defaults.dictionary(forKey: "libraryFolderSortPreferences") as? [String: [String: String]] ?? [:]
        self.manualOrders = defaults.dictionary(forKey: "libraryManualOrders") as? [String: [String]] ?? [:]
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
        if !isIncludedByDefault(sourceURL) { excludedCompilationKeys.insert(manualKey(for: destinationURL)) }
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
        if oldRoot == newRoot { migrateManualOrder(from: oldURL, to: newURL) }
        let oldKey = key(for: oldURL, relativeTo: oldRoot)
        let newKey = key(for: newURL, relativeTo: newRoot)
        let oldLegacyKey = legacyKey(for: oldURL)
        if excludedCompilationKeys.remove(oldKey) != nil { excludedCompilationKeys.insert(newKey) }

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
        excludedCompilationKeys.remove(manualKey(for: url))
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
