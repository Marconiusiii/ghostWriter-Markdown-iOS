//
//  EBrailleEndToEndTests.swift
//  ghostWriterTests
//
//  Exercises the whole eBraille path with real liblouis translation rather than
//  a stub, because the packaging tests deliberately substitute a fake and would
//  not notice a translation failure reaching the file.
//

import Foundation
import Testing
import ZIPFoundation
@testable import ghostWriter

struct EBrailleEndToEndTests {

    @Test func realTranslationProducesConformingBrailleContent() async throws {
        let markdown = """
        # The Quick Report

        The quick brown fox knows braille. It exports 26 files.

        - First item
        - Second item
        """

        let data = try await EBrailleWriter.write(
            title: "The Quick Report",
            markdown: markdown,
            metadata: EBrailleMetadata(creator: "Marco", transcriber: "Marco", grade: .grade2, copyrightYear: "2026"),
            translator: LiblouisBridge.shared
        )

        let archive = try Archive(data: data, accessMode: .read)
        var content = ""
        for entry in archive where entry.path == "content.xhtml" {
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            content = String(decoding: bytes, as: UTF8.self)
        }

        #expect(!content.isEmpty)

        // No print words survive into the braille document.
        #expect(!content.contains("quick brown fox"))
        #expect(!content.contains("Quick Report"))

        // Real braille cells are present.
        let brailleCells = content.unicodeScalars.filter { (0x2800...0x28FF).contains($0.value) }
        #expect(brailleCells.count > 40)
    }

    @Test func gradeChoiceChangesTheBrailleInTheFile() async throws {
        let markdown = "The quick brown fox knows braille and reads it well."

        func cells(for grade: BrailleGrade) async throws -> Int {
            let data = try await EBrailleWriter.write(
                title: "Doc",
                markdown: markdown,
                metadata: EBrailleMetadata(creator: "Marco", transcriber: "Marco", grade: grade, copyrightYear: "2026"),
                translator: LiblouisBridge.shared
            )
            let archive = try Archive(data: data, accessMode: .read)
            var content = ""
            for entry in archive where entry.path == "content.xhtml" {
                var bytes = Data()
                _ = try archive.extract(entry) { bytes.append($0) }
                content = String(decoding: bytes, as: UTF8.self)
            }
            return content.unicodeScalars.filter { (0x2800...0x28FF).contains($0.value) }.count
        }

        // Contracted braille is materially shorter. Equal counts would mean the
        // grade choice never reached the translator.
        let grade1Cells = try await cells(for: .grade1)
        let grade2Cells = try await cells(for: .grade2)

        #expect(grade2Cells < grade1Cells)
    }
}
