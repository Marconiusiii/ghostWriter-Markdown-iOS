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

    @Test func launchAndNewDocumentDefaultsPreserveCurrentBehavior() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)

        #expect(settings.appLaunchBehavior == .showLibrary)
        #expect(settings.newDocumentCreationMode == .askForTitle)
    }

    @Test func launchAndNewDocumentPreferencesPersist() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)
        settings.appLaunchBehavior = .openLastDocument
        settings.newDocumentCreationMode = .useTodaysDate

        let restored = AppSettings(defaults: testDefaults.defaults)
        #expect(restored.appLaunchBehavior == .openLastDocument)
        #expect(restored.newDocumentCreationMode == .useTodaysDate)
    }

    @Test func invalidLaunchPreferencesFallBackSafely() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        testDefaults.defaults.set("invalid", forKey: "appLaunchBehavior")
        testDefaults.defaults.set("invalid", forKey: "newDocumentCreationMode")

        let settings = AppSettings(defaults: testDefaults.defaults)

        #expect(settings.appLaunchBehavior == .showLibrary)
        #expect(settings.newDocumentCreationMode == .askForTitle)
    }

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

    @Test func keyboardShortcutsDefaultToEnabledAndPersist() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)
        #expect(settings.keyboardShortcutsEnabled)

        settings.keyboardShortcutsEnabled = false
        let restored = AppSettings(defaults: testDefaults.defaults)
        #expect(!restored.keyboardShortcutsEnabled)
    }

    @Test func voiceOverVerbosityDefaultsToLightAndPersists() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let settings = AppSettings(defaults: testDefaults.defaults)
        #expect(settings.voiceOverVerbosity == .light)

        settings.voiceOverVerbosity = .full
        let restored = AppSettings(defaults: testDefaults.defaults)
        #expect(restored.voiceOverVerbosity == .full)
    }

    @Test func invalidVoiceOverVerbosityFallsBackToLight() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }
        testDefaults.defaults.set("verbose", forKey: "voiceOverVerbosity")

        let settings = AppSettings(defaults: testDefaults.defaults)

        #expect(settings.voiceOverVerbosity == .light)
    }

    @Test func voiceOverVerbosityDescriptionsStayConcise() {
        #expect(
            VoiceOverVerbosity.off.description
                == "No Markdown editing announcements."
        )
        #expect(
            VoiceOverVerbosity.light.description
                == "Announces list changes, indentation levels, and Insert actions."
        )
        #expect(
            VoiceOverVerbosity.full.description
                == "Announces Light feedback and completed Markdown structures as you type."
        )
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ghostWriterTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanUp(_ testDefaults: (defaults: UserDefaults, suiteName: String)) {
        testDefaults.defaults.removePersistentDomain(forName: testDefaults.suiteName)
    }
}
