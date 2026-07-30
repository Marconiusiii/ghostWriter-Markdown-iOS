//
//  EditorPositionStore.swift
//  ghostWriter
//
//  Remembers a document's last insertion point without adding metadata to the
//  writer's markdown file. Positions use Swift Character offsets, matching the
//  editor, Outline, and Status Bar.
//

import Foundation

final class EditorPositionStore {
    static let shared = EditorPositionStore()

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "documentEditingPositions"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func position(for url: URL) -> Int? {
        positions[key(for: url)] ?? positions[legacyKey(for: url)]
    }

    func save(position: Int, for url: URL) {
        var updated = positions
        updated[key(for: url)] = max(0, position)
        defaults.set(updated, forKey: storageKey)
    }

    func migratePosition(from oldURL: URL, to newURL: URL) {
        let oldKey = key(for: oldURL)
        let newKey = key(for: newURL)
        let oldLegacyKey = legacyKey(for: oldURL)

        var updated = positions
        let stablePosition = updated.removeValue(forKey: oldKey)
        let legacyPosition = updated.removeValue(forKey: oldLegacyKey)
        let position = stablePosition ?? legacyPosition
        if let position {
            updated[newKey] = position
            defaults.set(updated, forKey: storageKey)
        }
    }

    func removePosition(for url: URL) {
        var updated = positions
        let removedStable = updated.removeValue(forKey: key(for: url))
        let removedLegacy = updated.removeValue(forKey: legacyKey(for: url))
        guard removedStable != nil || removedLegacy != nil else { return }
        defaults.set(updated, forKey: storageKey)
    }

    private var positions: [String: Int] {
        defaults.dictionary(forKey: storageKey)?.reduce(into: [:]) { result, item in
            if let value = item.value as? NSNumber {
                result[item.key] = max(0, value.intValue)
            }
        } ?? [:]
    }

    private func key(for url: URL) -> String {
        DocumentStorageKey.key(for: url)
    }

    private func legacyKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
