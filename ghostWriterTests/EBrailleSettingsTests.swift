//
//  EBrailleSettingsTests.swift
//  ghostWriterTests
//
//  The eBraille options are remembered between exports, so that producing a
//  second file is a matter of confirming rather than retyping four answers.
//  These cover the persistence and the defaults.
//

import Foundation
import Testing
@testable import ghostWriter

struct EBrailleSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "eBrailleSettingsTests-\(UUID().uuidString)")!
        return suite
    }

    @Test func optionsAreRememberedAcrossSessions() {
        let defaults = makeDefaults()

        let first = AppSettings(defaults: defaults)
        first.eBrailleCreator = "Marco Salsiccia"
        first.eBrailleTranscriber = "Braille Services Ltd"
        first.eBrailleCopyrightYear = "2026"
        first.eBrailleGrade = .grade1
        first.eBrailleCompleteTranscription = false
        first.eBrailleSource = "urn:isbn:9780000000001"
        first.eBraillePublisher = "A Braille Press"
        first.eBrailleRights = "Transcribed under licence."
        first.eBrailleSubject = "Geography"
        first.eBrailleDescription = "A short report."
        first.eBrailleEducationLevel = "Year 4"

        // A fresh instance stands in for the next launch.
        let second = AppSettings(defaults: defaults)

        #expect(second.eBrailleCreator == "Marco Salsiccia")
        #expect(second.eBrailleTranscriber == "Braille Services Ltd")
        #expect(second.eBrailleCopyrightYear == "2026")
        #expect(second.eBrailleGrade == .grade1)
        #expect(second.eBrailleCompleteTranscription == false)
        #expect(second.eBrailleSource == "urn:isbn:9780000000001")
        #expect(second.eBraillePublisher == "A Braille Press")
        #expect(second.eBrailleRights == "Transcribed under licence.")
        #expect(second.eBrailleSubject == "Geography")
        #expect(second.eBrailleDescription == "A short report.")
        #expect(second.eBrailleEducationLevel == "Year 4")
    }

    @Test func gradeTwoIsTheDefault() {
        let settings = AppSettings(defaults: makeDefaults())

        // Contracted braille is what most braille readers prefer.
        #expect(settings.eBrailleGrade == .grade2)
        #expect(settings.eBrailleCompleteTranscription == true)
        #expect(settings.eBrailleCreator.isEmpty)
    }

    @Test func emptyOptionsStillProduceValidMetadata() {
        let metadata = EBrailleMetadata(creator: "", grade: .grade2, copyrightYear: "")

        // Both fields are required by the standard, so neither can be left out
        // of the file when the writer skips them. The creator names the author
        // of the work, so it must not fall back to the software's name.
        #expect(metadata.effectiveCreator == EBrailleMetadata.unknownCreator)
        #expect(metadata.effectiveCreator != EBrailleMetadata.producerSoftware)
        #expect(!metadata.effectiveCopyrightYear.isEmpty)
        #expect(metadata.effectiveCopyrightYear.count == 4)
        #expect(metadata.effectiveProducers == [EBrailleMetadata.producerSoftware])
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

    @Test func unusableCopyrightDateFallsBackToTheCurrentYear() {
        let metadata = EBrailleMetadata(copyrightYear: "202")
        let thisYear = String(Calendar.current.component(.year, from: Date()))

        // A half-typed date would make the file non-conforming, so it is
        // replaced rather than written through.
        #expect(metadata.effectiveCopyrightYear == thisYear)
        #expect(!metadata.hasUsableCopyrightYear)
        #expect(EBrailleMetadata(copyrightYear: "").hasUsableCopyrightYear)
        #expect(EBrailleMetadata(copyrightYear: "2026-04").hasUsableCopyrightYear)
    }

    @Test func namingTheSoftwareAsTranscriberDoesNotDuplicateTheProducer() {
        let metadata = EBrailleMetadata(transcriber: "ghostWriter Markdown")

        // a11y:producer may repeat, but listing the same name twice says
        // nothing and reads as a mistake.
        #expect(metadata.effectiveProducers == [EBrailleMetadata.producerSoftware])
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
