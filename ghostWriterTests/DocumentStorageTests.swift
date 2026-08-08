//
//  DocumentStorageTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct DocumentStorageTests {
    @Test func usesGhostWriterMarkdownICloudContainer() {
        #expect(
            DocumentStorage.containerIdentifier
                == "iCloud.com.marconius.ghostwritermarkdown"
        )
    }

    @Test func defaultsToOnDeviceStorage() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let localDirectory = temporaryDirectory("local")
        defer { try? FileManager.default.removeItem(at: localDirectory) }

        let storage = DocumentStorage(
            defaults: testDefaults.defaults,
            localDirectory: localDirectory
        )

        #expect(storage.selectedLocation == .onDevice)
        #expect(storage.activeDirectory == localDirectory)
    }

    @Test func selectedLocationPersistsOnlyOnThisInstallation() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let localDirectory = temporaryDirectory("local")
        defer { try? FileManager.default.removeItem(at: localDirectory) }

        let storage = DocumentStorage(
            defaults: testDefaults.defaults,
            localDirectory: localDirectory
        )
        storage.select(.iCloud)

        let restored = DocumentStorage(
            defaults: testDefaults.defaults,
            localDirectory: localDirectory
        )
        #expect(restored.selectedLocation == .iCloud)
    }

    @Test func iCloudDoesNotBecomeActiveUntilItIsResolved() async {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let localDirectory = temporaryDirectory("local")
        let cloudDirectory = temporaryDirectory("cloud")
        defer {
            try? FileManager.default.removeItem(at: localDirectory)
            try? FileManager.default.removeItem(at: cloudDirectory)
        }

        let storage = DocumentStorage(
            defaults: testDefaults.defaults,
            localDirectory: localDirectory,
            resolveICloudContainer: { .available(cloudDirectory) }
        )
        storage.select(.iCloud)

        #expect(storage.activeDirectory == nil)
        #expect(await storage.prepareCurrentLocation() == cloudDirectory)
        #expect(storage.activeDirectory == cloudDirectory)
    }

    @Test func unavailableICloudNeverFallsBackToLocalFiles() async {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        let localDirectory = temporaryDirectory("local")
        defer { try? FileManager.default.removeItem(at: localDirectory) }

        let storage = DocumentStorage(
            defaults: testDefaults.defaults,
            localDirectory: localDirectory,
            resolveICloudContainer: {
                .unavailable("iCloud is unavailable for this test.")
            }
        )
        storage.select(.iCloud)

        #expect(await storage.prepareCurrentLocation() == nil)
        #expect(storage.activeDirectory == nil)
        #expect(
            storage.statusDescription
                == "iCloud is unavailable for this test."
        )
    }

    @Test func documentKeyIsStableAcrossDeviceContainerPaths() {
        let local = URL(
            fileURLWithPath: "/local/Application/Documents/ghostWriter/Note.md"
        )
        let cloud = URL(
            fileURLWithPath: "/mobile/Library/Mobile Documents/container/Documents/Note.md"
        )

        #expect(DocumentStorageKey.key(for: local) == "Note.md")
        #expect(DocumentStorageKey.key(for: cloud) == "Note.md")
    }

    @Test func recentlyDeletedRemainsPartOfTheStableKey() {
        let url = URL(
            fileURLWithPath: "/container/Documents/Recently Deleted/Note.md"
        )

        #expect(
            DocumentStorageKey.key(for: url)
                == "Recently Deleted/Note.md"
        )
    }

    private func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "ghostWriterStorage-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ghostWriterStorageTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanUp(
        _ testDefaults: (defaults: UserDefaults, suiteName: String)
    ) {
        testDefaults.defaults.removePersistentDomain(
            forName: testDefaults.suiteName
        )
    }
}
