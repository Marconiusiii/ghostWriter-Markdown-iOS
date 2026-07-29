//
//  SortOrderTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct SortOrderTests {

    @Test func pinnedDocumentsRemainFirstInAscendingOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.metadata.togglePin(for: fixture.newer.url)
        let sort = DocumentSort(field: .name, direction: .ascending)

        let result = sort.sorted(
            [fixture.older, fixture.newer],
            metadata: fixture.metadata
        )

        #expect(result.map(\.url) == [fixture.newer.url, fixture.older.url])
    }

    @Test func pinnedDocumentsRemainFirstInDescendingOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.metadata.togglePin(for: fixture.older.url)
        let sort = DocumentSort(field: .name, direction: .descending)

        let result = sort.sorted(
            [fixture.older, fixture.newer],
            metadata: fixture.metadata
        )

        #expect(result.first?.url == fixture.older.url)
    }

    @Test func lastOpenedSortsNewestFirst() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.metadata.recordOpened(
            fixture.older.url,
            at: Date(timeIntervalSince1970: 100)
        )
        fixture.metadata.recordOpened(
            fixture.newer.url,
            at: Date(timeIntervalSince1970: 200)
        )
        let sort = DocumentSort(
            field: .lastOpened,
            direction: .descending
        )

        let result = sort.sorted(
            [fixture.older, fixture.newer],
            metadata: fixture.metadata
        )

        #expect(result.map(\.url) == [fixture.newer.url, fixture.older.url])
    }

    @Test func neverOpenedDocumentsSortBehindOpenedDocumentsWhenNewestFirst() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.metadata.recordOpened(fixture.newer.url)
        let sort = DocumentSort(
            field: .lastOpened,
            direction: .descending
        )

        let result = sort.sorted(
            [fixture.older, fixture.newer],
            metadata: fixture.metadata
        )

        #expect(result.map(\.url) == [fixture.newer.url, fixture.older.url])
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterSortTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let olderURL = directory.appendingPathComponent("Alpha.md")
        let newerURL = directory.appendingPathComponent("Zulu.md")
        try "older".write(to: olderURL, atomically: true, encoding: .utf8)
        try "newer".write(to: newerURL, atomically: true, encoding: .utf8)
        guard let older = Document(fileURL: olderURL),
              let newer = Document(fileURL: newerURL) else {
            throw FixtureError.couldNotCreateDocuments
        }
        let suiteName = "ghostWriterSortMetadata-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let metadata = DocumentLibraryMetadataStore(
            defaults: defaults,
            pinnedStorageKey: "pins",
            lastOpenedStorageKey: "opened"
        )
        return Fixture(
            directory: directory,
            suiteName: suiteName,
            defaults: defaults,
            metadata: metadata,
            older: older,
            newer: newer
        )
    }
}

private struct Fixture {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults
    let metadata: DocumentLibraryMetadataStore
    let older: Document
    let newer: Document

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private enum FixtureError: Error {
    case couldNotCreateDocuments
}
