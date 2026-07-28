//
//  AppSettingsTests.swift
//  ghostWriterTests
//
//  Keeps editor readability preferences stable across launches.
//

import Foundation
import Testing
@testable import ghostWriter

struct AppSettingsTests {

    @Test func monospacedIsTheDefaultEditorFont() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)

        #expect(settings.editorFontDesign == .monospaced)
    }

    @Test func editorFontPersists() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)
        settings.editorFontDesign = .serif

        let restored = AppSettings(defaults: testDefaults.defaults)
        #expect(restored.editorFontDesign == .serif)
    }

    @Test func invalidEditorFontFallsBackSafely() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        testDefaults.defaults.set("unavailable-font", forKey: "editorFontDesign")

        let settings = AppSettings(defaults: testDefaults.defaults)

        #expect(settings.editorFontDesign == .monospaced)
    }

    @Test func statusBarDefaultsAreUsefulButOptIn() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)

        #expect(!settings.statusBarEnabled)
        #expect(settings.statusShowsLineAndColumn)
        #expect(settings.statusShowsLineCount)
        #expect(settings.statusShowsWordCount)
        #expect(settings.statusShowsCharacterCount)
        #expect(!settings.statusShowsHeadingLevel)
        #expect(!settings.statusShowsSelectedWordCount)
        #expect(!settings.statusShowsSelectedCharacterCount)
    }

    @Test func statusBarPreferencesPersist() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)
        settings.statusBarEnabled = true
        settings.statusShowsLineCount = false
        settings.statusShowsHeadingLevel = true
        settings.statusShowsSelectedCharacterCount = true

        let restored = AppSettings(defaults: testDefaults.defaults)
        #expect(restored.statusBarEnabled)
        #expect(!restored.statusShowsLineCount)
        #expect(restored.statusShowsHeadingLevel)
        #expect(restored.statusShowsSelectedCharacterCount)
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ghostWriterTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanUp(_ testDefaults: (defaults: UserDefaults, suiteName: String)) {
        testDefaults.defaults.removePersistentDomain(forName: testDefaults.suiteName)
    }
}
