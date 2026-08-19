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
        first.eBrailleCopyrightYear = "2026"
        first.eBrailleGrade = .grade1
        first.eBrailleCompleteTranscription = false

        // A fresh instance stands in for the next launch.
        let second = AppSettings(defaults: defaults)

        #expect(second.eBrailleCreator == "Marco Salsiccia")
        #expect(second.eBrailleCopyrightYear == "2026")
        #expect(second.eBrailleGrade == .grade1)
        #expect(second.eBrailleCompleteTranscription == false)
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
        // of the file when the writer skips them.
        #expect(metadata.effectiveCreator == EBrailleMetadata.producer)
        #expect(!metadata.effectiveCopyrightYear.isEmpty)
        #expect(metadata.effectiveCopyrightYear.count == 4)
    }

    @Test func onlyEBrailleRequiresOptions() {
        // Every other format is derivable from the document alone, so none of
        // them should stop to ask.
        for format in EditorView.EditorShareFormat.allCases {
            #expect(format.requiresOptions == (format == .eBraille))
        }
    }
}
