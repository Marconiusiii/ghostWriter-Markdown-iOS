//
//  NewDocumentCreationModeTests.swift
//  ghostWriterTests
//


import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct NewDocumentCreationModeTests {
    @Test func todayUsesTheWritersLongLocalizedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let date = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 3)
            )
        )

        let title = NewDocumentTitle.today(
            date: date,
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: timeZone
        )

        #expect(title == "August 3, 2026")
    }

    @Test func repeatedDateTitlesDoNotOverwriteDocuments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterDateTitleTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = DocumentStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try #require(
            store.createDocument(named: "August 3, 2026")
        )
        let second = try #require(
            store.createDocument(named: "August 3, 2026")
        )

        #expect(first.lastPathComponent == "August 3, 2026.md")
        #expect(second.lastPathComponent == "August 3, 2026 2.md")
        #expect(first != second)
    }
}
