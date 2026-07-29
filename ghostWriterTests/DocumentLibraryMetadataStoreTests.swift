//
//  DocumentLibraryMetadataStoreTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct DocumentLibraryMetadataStoreTests {

    @Test func pinStatePersists() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let url = URL(fileURLWithPath: "/tmp/Pinned.md")
        let store = makeStore(testDefaults.defaults)

        store.togglePin(for: url)

        let restored = makeStore(testDefaults.defaults)
        #expect(restored.isPinned(url))
    }

    @Test func openingDatePersists() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let url = URL(fileURLWithPath: "/tmp/Opened.md")
        let date = Date(timeIntervalSince1970: 1_234)
        let store = makeStore(testDefaults.defaults)

        store.recordOpened(url, at: date)

        let restored = makeStore(testDefaults.defaults)
        #expect(restored.lastOpened(url) == date)
    }

    @Test func migrationMovesPinAndOpeningDate() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let oldURL = URL(fileURLWithPath: "/tmp/Before.md")
        let newURL = URL(fileURLWithPath: "/tmp/After.md")
        let date = Date(timeIntervalSince1970: 5_678)
        let store = makeStore(testDefaults.defaults)
        store.togglePin(for: oldURL)
        store.recordOpened(oldURL, at: date)

        store.migrateMetadata(from: oldURL, to: newURL)

        #expect(!store.isPinned(oldURL))
        #expect(store.lastOpened(oldURL) == nil)
        #expect(store.isPinned(newURL))
        #expect(store.lastOpened(newURL) == date)
    }

    @Test func permanentDeletionRemovesAllMetadata() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let url = URL(fileURLWithPath: "/tmp/Deleted.md")
        let store = makeStore(testDefaults.defaults)
        store.togglePin(for: url)
        store.recordOpened(url)

        store.removeMetadata(for: url)

        #expect(!store.isPinned(url))
        #expect(store.lastOpened(url) == nil)
    }

    private func makeStore(_ defaults: UserDefaults) -> DocumentLibraryMetadataStore {
        DocumentLibraryMetadataStore(
            defaults: defaults,
            pinnedStorageKey: "testPins",
            lastOpenedStorageKey: "testLastOpened"
        )
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ghostWriterLibraryMetadataTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanUp(_ testDefaults: (defaults: UserDefaults, suiteName: String)) {
        testDefaults.defaults.removePersistentDomain(forName: testDefaults.suiteName)
    }
}
