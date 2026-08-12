//
//  DocumentLibraryMetadataStoreTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct DocumentLibraryMetadataStoreTests {

    @Test func libraryPresentationCachesSortedRowsAndFolderCounts() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let metadata = makeStore(testDefaults.defaults)
        let root = URL(fileURLWithPath: "/library", isDirectory: true)
        metadata.useLibraryRoot(root)
        let pinned = Document(
            url: root.appendingPathComponent("Pinned.md"),
            created: Date(timeIntervalSince1970: 100),
            modified: Date(timeIntervalSince1970: 100),
            byteCount: 10
        )
        let recent = Document(
            url: root.appendingPathComponent("Recent.md"),
            created: Date(timeIntervalSince1970: 200),
            modified: Date(timeIntervalSince1970: 200),
            byteCount: 20
        )
        let folder = LibraryFolder(
            url: root.appendingPathComponent("Projects", isDirectory: true)
        )
        let nested = Document(
            url: folder.url.appendingPathComponent("Nested.md"),
            created: Date(timeIntervalSince1970: 300),
            modified: Date(timeIntervalSince1970: 300),
            byteCount: 30
        )
        metadata.togglePin(for: pinned.url)

        let snapshot = LibraryPresentationSnapshot.build(
            documents: [recent, nested, pinned],
            folders: [folder],
            currentDirectory: root,
            query: "",
            searchIndex: .empty,
            sort: DocumentSort(
                field: .modified,
                direction: .descending
            ),
            metadata: metadata
        )

        #expect(snapshot.documents.map(\.document) == [pinned, recent])
        #expect(snapshot.documents.first?.isPinned == true)
        #expect(snapshot.documents.first?.accessibilityLabel.contains("Pinned.md") == false)
        #expect(snapshot.documents.first?.accessibilityLabel.contains("Pinned") == true)
        #expect(snapshot.folders.first?.itemCount == 1)
        #expect(snapshot.currentItemCount == 3)
    }

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

    @Test func mostRecentlyOpenedDocumentIgnoresMissingHistory() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let store = makeStore(testDefaults.defaults)
        let older = document("/tmp/Older.md")
        let newer = document("/tmp/Newer.md")
        let neverOpened = document("/tmp/Never Opened.md")
        store.recordOpened(
            older.url,
            at: Date(timeIntervalSince1970: 100)
        )
        store.recordOpened(
            newer.url,
            at: Date(timeIntervalSince1970: 200)
        )

        let result = store.mostRecentlyOpenedDocument(
            in: [neverOpened, newer, older]
        )

        #expect(result == newer)
    }

    @Test func mostRecentlyOpenedDocumentReturnsNilWithoutHistory() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let store = makeStore(testDefaults.defaults)

        #expect(
            store.mostRecentlyOpenedDocument(
                in: [document("/tmp/Never Opened.md")]
            ) == nil
        )
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

    @Test func metadataFollowsTheDocumentFromLocalStorageToICloud() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let localURL = URL(
            fileURLWithPath: "/local/Documents/ghostWriter/Note.md"
        )
        let cloudURL = URL(
            fileURLWithPath: "/cloud/Documents/Note.md"
        )
        let date = Date(timeIntervalSince1970: 9_876)
        let store = makeStore(testDefaults.defaults)
        store.togglePin(for: localURL)
        store.recordOpened(localURL, at: date)

        store.migrateMetadata(from: localURL, to: cloudURL)

        #expect(store.isPinned(cloudURL))
        #expect(store.lastOpened(cloudURL) == date)
    }

    @Test func legacyAbsolutePathMetadataIsMigrated() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let oldURL = URL(
            fileURLWithPath: "/local/Documents/ghostWriter/Note.md"
        )
        let cloudURL = URL(
            fileURLWithPath: "/cloud/Documents/Note.md"
        )
        testDefaults.defaults.set(
            [oldURL.standardizedFileURL.path],
            forKey: "testPins"
        )
        let store = makeStore(testDefaults.defaults)

        store.migrateMetadata(from: oldURL, to: cloudURL)

        #expect(store.isPinned(cloudURL))
    }

    private func makeStore(_ defaults: UserDefaults) -> DocumentLibraryMetadataStore {
        DocumentLibraryMetadataStore(
            defaults: defaults,
            pinnedStorageKey: "testPins",
            lastOpenedStorageKey: "testLastOpened"
        )
    }

    private func document(_ path: String) -> Document {
        Document(
            url: URL(fileURLWithPath: path),
            created: .distantPast,
            modified: .distantPast,
            byteCount: 0
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
