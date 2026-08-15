//
//  DocumentMigrationTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct DocumentMigrationTests {
    @Test func migrationPreservesNestedEmptyFolders() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }
        let emptyFolder = directories.source
            .appendingPathComponent("Projects/Archive", isDirectory: true)
        try FileManager.default.createDirectory(
            at: emptyFolder,
            withIntermediateDirectories: true
        )

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination
        )

        #expect(result.cleanupFailures.isEmpty)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: directories.destination
                .appendingPathComponent("Projects/Archive").path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
    }

    @Test func migratesAndVerifiesTheWholeLibrary() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let note = directories.source.appendingPathComponent("Note.md")
        let deletedDirectory = directories.source
            .appendingPathComponent("Recently Deleted", isDirectory: true)
        let deleted = deletedDirectory.appendingPathComponent("Old.txt")
        try FileManager.default.createDirectory(
            at: deletedDirectory,
            withIntermediateDirectories: true
        )
        try "Current".write(to: note, atomically: true, encoding: .utf8)
        try "Deleted".write(to: deleted, atomically: true, encoding: .utf8)

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination
        )

        #expect(result.migrated.count == 2)
        #expect(result.cleanupFailures.isEmpty)
        #expect(
            try String(
                contentsOf: directories.destination
                    .appendingPathComponent("Note.md"),
                encoding: .utf8
            ) == "Current"
        )
        #expect(
            try String(
                contentsOf: directories.destination
                    .appendingPathComponent("Recently Deleted/Old.txt"),
                encoding: .utf8
            ) == "Deleted"
        )
        #expect(!FileManager.default.fileExists(atPath: note.path))
        #expect(!FileManager.default.fileExists(atPath: deleted.path))
    }

    @Test func migrationPreservesHiddenDocumentImageAssets() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }
        let assetName = ".ghostwriter-assets-33333333-3333-3333-3333-333333333333"
        let document = directories.source.appendingPathComponent("Images.md")
        let assetDirectory = directories.source.appendingPathComponent(
            assetName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: assetDirectory,
            withIntermediateDirectories: true
        )
        try "![Description](\(assetName)/image.png)".write(
            to: document,
            atomically: true,
            encoding: .utf8
        )
        try Data([1, 2, 3]).write(
            to: assetDirectory.appendingPathComponent("image.png")
        )

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination
        )

        #expect(result.cleanupFailures.isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: directories.destination
                .appendingPathComponent(assetName)
                .appendingPathComponent("image.png").path
        ))
        #expect(!FileManager.default.fileExists(atPath: assetDirectory.path))
    }

    @Test func assetDirectoryCollisionKeepsBothDocumentsImagesConnected() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }
        let assetName = ".ghostwriter-assets-44444444-4444-4444-4444-444444444444"
        let sourceAssets = directories.source.appendingPathComponent(assetName)
        let destinationAssets = directories.destination.appendingPathComponent(assetName)
        try FileManager.default.createDirectory(at: sourceAssets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationAssets, withIntermediateDirectories: true)
        try "![Incoming](\(assetName)/image.png)".write(
            to: directories.source.appendingPathComponent("Images.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data([1]).write(to: sourceAssets.appendingPathComponent("image.png"))
        try Data([2]).write(to: destinationAssets.appendingPathComponent("image.png"))

        _ = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination
        )

        let markdown = try String(
            contentsOf: directories.destination.appendingPathComponent("Images.md"),
            encoding: .utf8
        )
        let migratedName = try #require(DocumentAssets.directoryNames(in: markdown).first)
        #expect(migratedName != assetName)
        #expect(try Data(contentsOf: directories.destination
            .appendingPathComponent(migratedName)
            .appendingPathComponent("image.png")) == Data([1]))
        #expect(try Data(contentsOf: destinationAssets
            .appendingPathComponent("image.png")) == Data([2]))
    }

    @Test func destinationCollisionPreservesBothDocuments() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let source = directories.source.appendingPathComponent("Note.md")
        let existing = directories.destination.appendingPathComponent("Note.md")
        try "Incoming".write(to: source, atomically: true, encoding: .utf8)
        try "Existing".write(to: existing, atomically: true, encoding: .utf8)

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination
        )

        #expect(result.migrated.first?.destinationURL.lastPathComponent == "Note 2.md")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Existing")
        #expect(
            try String(
                contentsOf: directories.destination
                    .appendingPathComponent("Note 2.md"),
                encoding: .utf8
            ) == "Incoming"
        )
    }

    @Test func pristineWelcomeReusesAnEditedDestination() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let source = directories.source.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let existing = directories.destination.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let pristine = Data("Bundled Welcome".utf8)
        try pristine.write(to: source)
        try "Edited iCloud Welcome".write(
            to: existing,
            atomically: true,
            encoding: .utf8
        )

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination,
            reusableSourceTemplates: [WelcomeDocument.fileName: pristine]
        )

        #expect(result.migrated.count == 1)
        #expect(result.migrated[0].destinationURL == existing)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(
            try String(contentsOf: existing, encoding: .utf8)
                == "Edited iCloud Welcome"
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: directories.destination
                    .appendingPathComponent(
                        "Welcome to ghostWriter Markdown 2.md"
                    ).path
            )
        )
    }

    @Test func pristineWelcomeReusesAnIdenticalDestination() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let source = directories.source.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let existing = directories.destination.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let pristine = Data("Bundled Welcome".utf8)
        try pristine.write(to: source)
        try pristine.write(to: existing)

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination,
            reusableSourceTemplates: [WelcomeDocument.fileName: pristine]
        )

        #expect(result.migrated.first?.destinationURL == existing)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: existing) == pristine)
    }

    @Test func editedLocalWelcomeStillPreservesBothDocuments() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let source = directories.source.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let existing = directories.destination.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let pristine = Data("Bundled Welcome".utf8)
        try "Edited local Welcome".write(
            to: source,
            atomically: true,
            encoding: .utf8
        )
        try "Existing iCloud Welcome".write(
            to: existing,
            atomically: true,
            encoding: .utf8
        )

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination,
            reusableSourceTemplates: [WelcomeDocument.fileName: pristine]
        )
        let numbered = directories.destination.appendingPathComponent(
            "Welcome to ghostWriter Markdown 2.md"
        )

        #expect(result.migrated.first?.destinationURL == numbered)
        #expect(
            try String(contentsOf: existing, encoding: .utf8)
                == "Existing iCloud Welcome"
        )
        #expect(
            try String(contentsOf: numbered, encoding: .utf8)
                == "Edited local Welcome"
        )
    }

    @Test func pristineWelcomeMovesNormallyWithoutADestination() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let source = directories.source.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let destination = directories.destination.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let pristine = Data("Bundled Welcome".utf8)
        try pristine.write(to: source)

        let result = try DocumentMigration().migrate(
            from: directories.source,
            to: directories.destination,
            reusableSourceTemplates: [WelcomeDocument.fileName: pristine]
        )

        #expect(result.migrated.first?.destinationURL == destination)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: destination) == pristine)
    }

    @Test func laterFailureNeverDeletesAReusedICloudWelcome() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let welcomeSource = directories.source.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let failureSource = directories.source.appendingPathComponent(
            "Z Migration Failure.md"
        )
        let existing = directories.destination.appendingPathComponent(
            WelcomeDocument.fileName
        )
        let pristine = Data("Bundled Welcome".utf8)
        try pristine.write(to: welcomeSource)
        try "Trigger failure".write(
            to: failureSource,
            atomically: true,
            encoding: .utf8
        )
        try "Existing iCloud Welcome".write(
            to: existing,
            atomically: true,
            encoding: .utf8
        )
        let migration = DocumentMigration(
            placeUbiquitousItem: { _, _ in
                throw CocoaError(.fileWriteUnknown)
            }
        )

        #expect(throws: (any Error).self) {
            try migration.migrate(
                from: directories.source,
                to: directories.destination,
                destinationUsesICloud: true,
                reusableSourceTemplates: [
                    WelcomeDocument.fileName: pristine
                ]
            )
        }

        #expect(FileManager.default.fileExists(atPath: welcomeSource.path))
        #expect(FileManager.default.fileExists(atPath: failureSource.path))
        #expect(
            try String(contentsOf: existing, encoding: .utf8)
                == "Existing iCloud Welcome"
        )
    }

    @Test func failedMigrationLeavesTheSourceUntouched() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }

        let source = directories.source.appendingPathComponent("Note.md")
        try "Keep me".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: directories.destination)
        try "Not a directory".write(
            to: directories.destination,
            atomically: true,
            encoding: .utf8
        )

        #expect(throws: (any Error).self) {
            try DocumentMigration().migrate(
                from: directories.source,
                to: directories.destination
            )
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "Keep me")
    }

    @Test func iCloudMigrationUsesStagedPlacementBeforeCleanup() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }
        let source = directories.source.appendingPathComponent("Note.md")
        try "Move through staging".write(
            to: source,
            atomically: true,
            encoding: .utf8
        )
        var placementCount = 0
        let migration = DocumentMigration(
            placeUbiquitousItem: { data, destination in
                placementCount += 1
                try data.write(to: destination, options: .atomic)
            }
        )

        let result = try migration.migrate(
            from: directories.source,
            to: directories.destination,
            destinationUsesICloud: true
        )

        #expect(placementCount == 1)
        #expect(result.migrated.count == 1)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(
            try String(
                contentsOf: result.migrated[0].destinationURL,
                encoding: .utf8
            ) == "Move through staging"
        )
    }

    @Test func failedICloudPlacementLeavesTheSourceUntouched() throws {
        let directories = try makeDirectories()
        defer { cleanUp(directories.root) }
        let source = directories.source.appendingPathComponent("Note.md")
        try "Keep me".write(
            to: source,
            atomically: true,
            encoding: .utf8
        )
        let migration = DocumentMigration(
            placeUbiquitousItem: { _, _ in
                throw CocoaError(.fileWriteUnknown)
            }
        )

        #expect(throws: (any Error).self) {
            try migration.migrate(
                from: directories.source,
                to: directories.destination,
                destinationUsesICloud: true
            )
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "Keep me")
    }

    private func makeDirectories() throws -> (
        root: URL,
        source: URL,
        destination: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterMigration-\(UUID().uuidString)",
                isDirectory: true
            )
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent(
            "Destination",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        return (root, source, destination)
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
