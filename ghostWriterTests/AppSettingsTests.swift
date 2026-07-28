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

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ghostWriterTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanUp(_ testDefaults: (defaults: UserDefaults, suiteName: String)) {
        testDefaults.defaults.removePersistentDomain(forName: testDefaults.suiteName)
    }
}
