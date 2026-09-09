import Foundation
import CoreText
import Testing
@testable import ghostWriter

struct PowerPointThemeTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PowerPointThemeTests-\(UUID().uuidString)")!
    }

    @Test func fontSelectionIsRememberedIndependentlyAndInvalidValuesUseArial() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.powerPointFont == .arial)
        settings.powerPointFont = .georgia
        settings.powerPointTheme = .midnight
        let restored = AppSettings(defaults: defaults)
        #expect(restored.powerPointFont == .georgia)
        #expect(restored.powerPointTheme == .midnight)
        defaults.set("Not a supported font", forKey: "powerPointFont")
        #expect(AppSettings(defaults: defaults).powerPointFont == .arial)
    }

    @Test func supportedFontsHaveRealRegularAndEmphasisFaces() throws {
        for family in PowerPointFont.allCases {
            for bold in [false, true] {
                for italic in [false, true] {
                    let font = try #require(family.resolvedFont(size: 24, bold: bold, italic: italic),
                        "Missing \(family.rawValue), bold=\(bold), italic=\(italic)")
                    #expect(CTFontCopyFamilyName(font) as String == family.rawValue)
                }
            }
        }
    }

    @Test func everyAllowedTextPairHasEnhancedContrast() {
        for theme in PowerPointTheme.allCases {
            for pair in theme.palette.testedTextPairs {
                #expect(
                    PowerPointTheme.contrastRatio(
                        foreground: pair.foreground,
                        background: pair.background
                    ) >= 7.0,
                    "\(theme.rawValue): \(pair.foreground) on \(pair.background)"
                )
            }
        }
    }

    @Test func warmPaperIsTheDefaultAndSelectionIsRemembered() {
        let defaults = makeDefaults()
        #expect(AppSettings(defaults: defaults).powerPointTheme == .warmPaper)

        let first = AppSettings(defaults: defaults)
        first.powerPointTheme = .highContrastDark

        #expect(AppSettings(defaults: defaults).powerPointTheme == .highContrastDark)
    }
}
