//
//  CoordinatedFileAccessTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct CoordinatedFileAccessTests {
    @Test func verifiesReadableContentsAwayFromTheCaller() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterReadable-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let document = root.appendingPathComponent("Readable.md")
        try "Body".write(
            to: document,
            atomically: true,
            encoding: .utf8
        )

        try await CoordinatedFileAccess.verifyReadable(at: document)
    }

    @Test func coordinatesTheCompleteFileLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterCoordination-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }

        let access = CoordinatedFileAccess()
        let original = root.appendingPathComponent("Original.md")
        let copy = root.appendingPathComponent("Copy.md")
        let moved = root.appendingPathComponent("Moved.md")

        try access.createDirectory(at: root)
        try access.write("Body", to: original)
        #expect(try access.string(at: original) == "Body")

        try access.copyItem(at: original, to: copy)
        #expect(try access.data(at: original) == access.data(at: copy))

        try access.moveItem(at: copy, to: moved)
        #expect(!access.itemExists(at: copy))
        #expect(access.itemExists(at: moved))

        try access.removeItem(at: moved)
        #expect(!access.itemExists(at: moved))
        #expect(access.itemExists(at: original))
    }
}
