//
//  EditorPositionStoreTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct EditorPositionStoreTests {

    @Test func savesAndRestoresCharacterPosition() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let store = EditorPositionStore(defaults: testDefaults.defaults)
        let url = URL(fileURLWithPath: "/tmp/Draft.md")

        store.save(position: 125, for: url)

        let restored = EditorPositionStore(defaults: testDefaults.defaults)
        #expect(restored.position(for: url) == 125)
    }

    @Test func renameMigratesAndRemovesTheOldPosition() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let store = EditorPositionStore(defaults: testDefaults.defaults)
        let oldURL = URL(fileURLWithPath: "/tmp/Old.md")
        let newURL = URL(fileURLWithPath: "/tmp/New.md")

        store.save(position: 42, for: oldURL)
        store.migratePosition(from: oldURL, to: newURL)

        #expect(store.position(for: oldURL) == nil)
        #expect(store.position(for: newURL) == 42)
    }

    @Test func negativePositionsAreClamped() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let store = EditorPositionStore(defaults: testDefaults.defaults)
        let url = URL(fileURLWithPath: "/tmp/Draft.md")

        store.save(position: -10, for: url)

        #expect(store.position(for: url) == 0)
    }

    @Test func permanentDeletionRemovesSavedPosition() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let store = EditorPositionStore(defaults: testDefaults.defaults)
        let url = URL(fileURLWithPath: "/tmp/Deleted.md")

        store.save(position: 88, for: url)
        store.removePosition(for: url)

        #expect(store.position(for: url) == nil)
    }

    @Test func positionFollowsTheDocumentFromLocalStorageToICloud() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let store = EditorPositionStore(defaults: testDefaults.defaults)
        let localURL = URL(
            fileURLWithPath: "/local/Documents/ghostWriter/Note.md"
        )
        let cloudURL = URL(fileURLWithPath: "/cloud/Documents/Note.md")

        store.save(position: 33, for: localURL)
        store.migratePosition(from: localURL, to: cloudURL)

        #expect(store.position(for: cloudURL) == 33)
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ghostWriterPositionTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanUp(_ testDefaults: (defaults: UserDefaults, suiteName: String)) {
        testDefaults.defaults.removePersistentDomain(forName: testDefaults.suiteName)
    }
}
