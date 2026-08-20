//
//  EBrailleSettingsTests.swift
//  ghostWriterTests
//
//  Reusable braille preferences are remembered. Metadata about one work is
//  deliberately kept out of global settings.
//

import Foundation
import Testing
@testable import ghostWriter

struct EBrailleSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "eBrailleSettingsTests-\(UUID().uuidString)")!
        return suite
    }

    @Test func reusableOptionsAreRememberedAcrossSessions() {
        let defaults = makeDefaults()

        let first = AppSettings(defaults: defaults)
        first.eBrailleTranscriber = "Braille Services Ltd"
        first.eBrailleGrade = .grade1
        first.brfCellsPerLine = 32
        first.brfLinesPerPage = 24

        // A fresh instance stands in for the next launch.
        let second = AppSettings(defaults: defaults)

        #expect(second.eBrailleTranscriber == "Braille Services Ltd")
        #expect(second.eBrailleGrade == .grade1)
        #expect(second.brfCellsPerLine == 32)
        #expect(second.brfLinesPerPage == 24)
    }

    @Test func gradeTwoIsTheDefault() {
        let settings = AppSettings(defaults: makeDefaults())

        // Contracted braille is what most braille readers prefer.
        #expect(settings.eBrailleGrade == .grade2)
    }

    @Test func requiredMetadataIsNeverInvented() {
        let metadata = EBrailleMetadata(creator: "", grade: .grade2, copyrightYear: "")

        #expect(metadata.effectiveCreator.isEmpty)
        #expect(metadata.effectiveCopyrightYear == nil)
        #expect(metadata.effectiveProducers.isEmpty)
        #expect(metadata.validationMessage != nil)
    }

    @Test func copyrightDatesAreNormalisedToTheThreeAllowedForms() {
        // The spec permits YYYY, YYYY-MM, and YYYY-MM-DD and nothing else.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026") == "2026")
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-04") == "2026-04")
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-04-17") == "2026-04-17")

        // Separators a writer might reasonably type mean the same date.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026/04/17") == "2026-04-17")
        #expect(EBrailleMetadata.normalizedCopyrightDate(" 2026.4.7 ") == "2026-04-07")

        // Detail that cannot be trusted is dropped rather than guessed at.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-13") == "2026")

        // A day the month does not have must not survive. Calendar rolls such
        // a date forward rather than rejecting it, so 30 February would
        // otherwise be written to the file as 2 March.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-02-30") == "2026-02")
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-04-31") == "2026-04")

        // A leap day that does exist is kept.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2024-02-29") == "2024-02-29")
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-02-29") == "2026-02")

        // Nothing usable at all.
        #expect(EBrailleMetadata.normalizedCopyrightDate("202") == nil)
        #expect(EBrailleMetadata.normalizedCopyrightDate("last year") == nil)
        #expect(EBrailleMetadata.normalizedCopyrightDate("") == nil)
    }

    @Test func unusableCopyrightDateIsRejectedInsteadOfReplaced() {
        let metadata = EBrailleMetadata(copyrightYear: "202")

        #expect(metadata.effectiveCopyrightYear == nil)
        #expect(metadata.validationMessage != nil)
    }

    @Test func transcriberIsRecordedExactlyAsEntered() {
        let metadata = EBrailleMetadata(transcriber: "ghostWriter Markdown")

        #expect(metadata.effectiveProducers == ["ghostWriter Markdown"])
    }

    @Test func brfPageSetupDefaultsToTheStandardBraillePage() {
        // 40 by 25 is the standard braille page. A file wrapped for the wrong
        // width reads badly on the device it lands on, so the default has to
        // be the one most hardware expects.
        let setup = BRFWriter.PageSetup.standard
        #expect(setup.cellsPerLine == 40)
        #expect(setup.linesPerPage == 25)
    }
}
