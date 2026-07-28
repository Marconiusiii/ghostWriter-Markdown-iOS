//
//  DocumentSearchIndexTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct DocumentSearchIndexTests {

    @Test func findsNamesAndContentsFromTheCachedSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("Travel.md")
        let second = directory.appendingPathComponent("Notes.md")
        try "Packing list".write(to: first, atomically: true, encoding: .utf8)
        try "A lighthouse at dusk".write(to: second, atomically: true, encoding: .utf8)

        let index = DocumentSearchIndex.build(from: [
            DocumentSearchSource(
                url: first,
                displayName: "Travel",
                modified: .distantPast,
                byteCount: 12
            ),
            DocumentSearchSource(
                url: second,
                displayName: "Notes",
                modified: .distantPast,
                byteCount: 20
            )
        ])

        #expect(index.matches(documentURL: first, displayName: "Travel", query: "travel"))
        #expect(index.matches(documentURL: second, displayName: "Notes", query: "LIGHTHOUSE"))
        #expect(!index.matches(documentURL: first, displayName: "Travel", query: "lighthouse"))
    }

    @Test func unreadableFilesStillMatchByName() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let index = DocumentSearchIndex.build(from: [
            DocumentSearchSource(
                url: missing,
                displayName: "Missing Draft",
                modified: .distantPast,
                byteCount: 0
            )
        ])

        #expect(index.matches(
            documentURL: missing,
            displayName: "Missing Draft",
            query: "draft"
        ))
        #expect(!index.matches(
            documentURL: missing,
            displayName: "Missing Draft",
            query: "contents"
        ))
    }
}
