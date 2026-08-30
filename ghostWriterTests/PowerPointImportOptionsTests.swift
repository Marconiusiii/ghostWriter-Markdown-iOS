import Foundation
import Testing
@testable import ghostWriter

struct PowerPointImportOptionsTests {
    @Test func defaultOptionsIncludeUsefulContentWithoutHiddenOrDecorativeMaterial() {
        let options = PowerPointImportOptions()
        #expect(options.slideText && options.tables && options.images && options.speakerNotes)
        #expect(options.textFormatting && options.links)
        #expect(!options.hiddenSlides && !options.decorativeImages && !options.slideNumbers && !options.dates && !options.footers)
    }

    @Test func optionsSerializeWithoutLosingDisabledChoices() throws {
        let options = PowerPointImportOptions(slideText: false, tables: false, images: false, speakerNotes: true, textFormatting: false, links: false, hiddenSlides: true, decorativeImages: true, slideNumbers: true, dates: true, footers: true)
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(PowerPointImportOptions.self, from: data) == options)
    }

    #if canImport(UIKit)
    @MainActor
    @Test func importChoicesPersistWithoutChangingExportTheme() throws {
        let name = "PowerPointImportOptions-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.powerPointTheme = .midnight
        settings.powerPointImportOptions.images = false
        settings.powerPointImportOptions.hiddenSlides = true
        let restored = AppSettings(defaults: defaults)
        #expect(!restored.powerPointImportOptions.images)
        #expect(restored.powerPointImportOptions.hiddenSlides)
        #expect(restored.powerPointTheme == .midnight)
        defaults.set(Data("invalid".utf8), forKey: "powerPointImportOptions")
        #expect(AppSettings(defaults: defaults).powerPointImportOptions == PowerPointImportOptions())
    }
    #endif
}
