//
//  EBrailleSettingsTests.swift
//  ghostWriterTests
//
//  eBraille defaults are remembered and mapped into each new export.
//

import Foundation
import Testing
@testable import ghostWriter

struct EBrailleSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "eBrailleSettingsTests-\(UUID().uuidString)")!
        return suite
    }

    @Test func exportDefaultsAreRememberedAcrossSessions() {
        let defaults = makeDefaults()

        let first = AppSettings(defaults: defaults)
        first.eBrailleCreator = "Morgan Author"
        first.eBrailleTranscriber = "Braille Services Ltd"
        first.eBrailleGrade = .grade1
        first.eBrailleCopyrightDate = "2026-08"
        first.eBrailleIsCompleteDocument = false
        first.eBrailleSource = "Source edition"
        first.eBraillePublisher = "Example Press"
        first.eBrailleRights = "Shared with permission"
        first.eBrailleSubject = "Accessible publishing"
        first.eBrailleDescription = "A sample description"
        first.eBrailleEducationLevel = "Adult"
        first.brfCellsPerLine = 32
        first.brfLinesPerPage = 24

        // A fresh instance stands in for the next launch.
        let second = AppSettings(defaults: defaults)

        #expect(
            second.eBrailleMetadataDefaults == EBrailleMetadata(
                creator: "Morgan Author",
                transcriber: "Braille Services Ltd",
                grade: .grade1,
                copyrightYear: "2026-08",
                isCompleteTranscription: false,
                source: "Source edition",
                publisher: "Example Press",
                rights: "Shared with permission",
                subject: "Accessible publishing",
                descriptionText: "A sample description",
                educationLevel: "Adult"
            )
        )
        #expect(second.brfCellsPerLine == 32)
        #expect(second.brfLinesPerPage == 24)
    }

    @Test func metadataDefaultsStartEmptyAndComplete() {
        let metadata = AppSettings(defaults: makeDefaults())
            .eBrailleMetadataDefaults

        #expect(metadata.creator.isEmpty)
        #expect(metadata.transcriber.isEmpty)
        #expect(metadata.grade == .grade2)
        #expect(metadata.copyrightYear.isEmpty)
        #expect(metadata.isCompleteTranscription)
        #expect(metadata.source.isEmpty)
        #expect(metadata.publisher.isEmpty)
        #expect(metadata.rights.isEmpty)
        #expect(metadata.subject.isEmpty)
        #expect(metadata.descriptionText.isEmpty)
        #expect(metadata.educationLevel.isEmpty)
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

        // Invalid detail rejects the whole value rather than changing the
        // publication fact the writer supplied.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-13") == nil)

        // A day the month does not have must not survive. Calendar rolls such
        // a date forward rather than rejecting it, so 30 February would
        // otherwise be written to the file as 2 March.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-02-30") == nil)
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-04-31") == nil)

        // A leap day that does exist is kept.
        #expect(EBrailleMetadata.normalizedCopyrightDate("2024-02-29") == "2024-02-29")
        #expect(EBrailleMetadata.normalizedCopyrightDate("2026-02-29") == nil)

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
