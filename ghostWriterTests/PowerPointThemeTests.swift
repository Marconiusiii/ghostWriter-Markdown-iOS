import Foundation
import Testing
@testable import ghostWriter

struct PowerPointThemeTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PowerPointThemeTests-\(UUID().uuidString)")!
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
