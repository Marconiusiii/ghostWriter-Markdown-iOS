//
//  DocumentMigrationTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct DocumentMigrationTests {
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
