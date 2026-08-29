//
//  PowerPointTheme.swift
//  ghostWriter
//
//  A small, fixed set of presentation themes. Every color pairing used by the
//  writer is declared here so contrast is testable rather than accidental.
//

import Foundation

nonisolated enum PowerPointTheme: String, CaseIterable, Identifiable, Sendable {
    case warmPaper
    case midnight
    case highContrastLight
    case highContrastDark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .warmPaper: return String(localized: "Warm paper")
        case .midnight: return String(localized: "Midnight")
        case .highContrastLight: return String(localized: "High contrast light")
        case .highContrastDark: return String(localized: "High contrast dark")
        }
    }

    struct Palette: Equatable, Sendable {
        let background: String
        let text: String
        let secondaryText: String
        let accent: String
        let accentSoft: String
        let accentText: String
        let link: String
        let border: String

        var testedTextPairs: [(foreground: String, background: String)] {
            [
                (text, background),
                (secondaryText, background),
                (accent, background),
                (link, background),
                (text, accentSoft),
                (accentText, accent)
            ]
        }
    }

    var palette: Palette {
        switch self {
        case .warmPaper:
            return Palette(
                background: "F5F0E8",
                text: "1F1B18",
                secondaryText: "534A42",
                accent: "23433A",
                accentSoft: "D7E4DD",
                accentText: "FFFAF3",
                link: "0D4F8F",
                border: "6B6258"
            )
        case .midnight:
            return Palette(
                background: "13100F",
                text: "F2EBE1",
                secondaryText: "D1C4B8",
                accent: "B7D7C9",
                accentSoft: "2B342F",
                accentText: "000000",
                link: "8DC2FF",
                border: "8E8378"
            )
        case .highContrastLight:
            return Palette(
                background: "FFFFFF",
                text: "000000",
                secondaryText: "333333",
                accent: "003366",
                accentSoft: "E6EEF5",
                accentText: "FFFFFF",
                link: "004D99",
                border: "595959"
            )
        case .highContrastDark:
            return Palette(
                background: "000000",
                text: "FFFFFF",
                secondaryText: "D9D9D9",
                accent: "FFD60A",
                accentSoft: "262626",
                accentText: "000000",
                link: "6CB6FF",
                border: "BFBFBF"
            )
        }
    }

    static func contrastRatio(foreground: String, background: String) -> Double {
        let first = relativeLuminance(foreground)
        let second = relativeLuminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func relativeLuminance(_ hex: String) -> Double {
        let value = Int(hex, radix: 16) ?? 0
        let components = [
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        ].map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * components[0]
            + 0.7152 * components[1]
            + 0.0722 * components[2]
    }
}

nonisolated struct PowerPointExportOptions: Equatable, Sendable {
    let theme: PowerPointTheme
}
