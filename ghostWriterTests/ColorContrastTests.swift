//
//  ColorContrastTests.swift
//  ghostWriterTests
//
//  Protects the authored app and rendered-document palettes from contrast
//  regressions in both light and dark appearances.
//

import Testing
import UIKit
@testable import ghostWriter

struct ColorContrastTests {
    @Test func lightPaletteMeetsWCAG22AA() throws {
        try validateAssetPalette(for: .light)
    }

    @Test func darkPaletteMeetsWCAG22AA() throws {
        try validateAssetPalette(for: .dark)
    }

    @Test func renderedDocumentPaletteMeetsWCAG22AA() {
        let html = HTMLTemplate.document(
            title: "Contrast",
            body: "<h1>Heading</h1><p><a href=\"https://example.com\">Link</a></p>",
            baseFontPointSize: 17
        )

        let light = WebPalette(
            page: "#f5f0e8",
            panel: "#fffaf3",
            accent: "#23433a",
            accentSoft: "#d7e4dd",
            border: "#8b7f70",
            text: "#1f1b18",
            muted: "#534a42",
            code: "#ece4d6",
            link: "#0d4f8f",
            focus: "#a83b12"
        )
        let dark = WebPalette(
            page: "#13100f",
            panel: "#1c1816",
            accent: "#b7d7c9",
            accentSoft: "#2b342f",
            border: "#6f665d",
            text: "#f2ebe1",
            muted: "#d1c4b8",
            code: "#312926",
            link: "#8dc2ff",
            focus: "#f28d49"
        )

        for palette in [light, dark] {
            for hex in palette.allHexValues {
                #expect(html.localizedCaseInsensitiveContains(hex))
            }
            validateWebPalette(palette)
        }
    }

    private func validateAssetPalette(
        for style: UIUserInterfaceStyle
    ) throws {
        let page = try resolvedColor("PageBackground", style: style)
        let panel = try resolvedColor("PanelBackground", style: style)
        let editor = try resolvedColor("EditorBackground", style: style)
        let text = try resolvedColor("GhostText", style: style)
        let muted = try resolvedColor("GhostMuted", style: style)
        let accent = try resolvedColor("GhostAccent", style: style)
        let link = try resolvedColor("GhostLink", style: style)
        let code = try resolvedColor("CodeBackground", style: style)
        let accentSoft = try resolvedColor("AccentSoft", style: style)
        let border = try resolvedColor("GhostBorder", style: style)
        let focus = try resolvedColor("GhostFocus", style: style)
        let controlFill = try resolvedColor("ControlFill", style: style)

        requireContrast(text, page, minimum: 4.5, "text on page")
        requireContrast(text, panel, minimum: 4.5, "text on panel")
        requireContrast(text, editor, minimum: 4.5, "editor text")
        requireContrast(muted, page, minimum: 4.5, "muted text on page")
        requireContrast(muted, panel, minimum: 4.5, "muted text on panel")
        requireContrast(accent, page, minimum: 4.5, "accent text on page")
        requireContrast(accent, panel, minimum: 4.5, "accent text on panel")
        requireContrast(link, page, minimum: 4.5, "link on page")
        requireContrast(link, panel, minimum: 4.5, "link on panel")
        requireContrast(text, code, minimum: 4.5, "text on code surface")
        requireContrast(text, accentSoft, minimum: 4.5, "text on accent surface")
        requireContrast(border, page, minimum: 3, "border against page")
        requireContrast(border, panel, minimum: 3, "border against panel")
        requireContrast(focus, page, minimum: 3, "focus against page")
        requireContrast(focus, panel, minimum: 3, "focus against panel")
        requireContrast(.white, controlFill, minimum: 4.5, "prominent control text")
        requireContrast(controlFill, page, minimum: 3, "control against page")
        requireContrast(controlFill, panel, minimum: 3, "control against panel")
    }

    private func validateWebPalette(_ palette: WebPalette) {
        let page = RGB(hex: palette.page)
        let panel = RGB(hex: palette.panel)
        let text = RGB(hex: palette.text)

        requireContrast(text, page, minimum: 4.5, "web text on page")
        requireContrast(text, panel, minimum: 4.5, "web text on panel")
        requireContrast(RGB(hex: palette.muted), page, minimum: 4.5, "web muted text")
        requireContrast(RGB(hex: palette.accent), page, minimum: 4.5, "web heading")
        requireContrast(RGB(hex: palette.link), page, minimum: 4.5, "web link")
        requireContrast(text, RGB(hex: palette.code), minimum: 4.5, "web code")
        requireContrast(text, RGB(hex: palette.accentSoft), minimum: 4.5, "web table heading")
        requireContrast(RGB(hex: palette.border), page, minimum: 3, "web border on page")
        requireContrast(RGB(hex: palette.border), panel, minimum: 3, "web border on panel")
        requireContrast(RGB(hex: palette.focus), page, minimum: 3, "web focus on page")
        requireContrast(RGB(hex: palette.focus), panel, minimum: 3, "web focus on panel")
    }

    private func resolvedColor(
        _ name: String,
        style: UIUserInterfaceStyle
    ) throws -> RGB {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let color = try #require(
            UIColor(named: name, in: nil, compatibleWith: traits),
            "Missing color asset: \(name)"
        )
        return RGB(color: color.resolvedColor(with: traits))
    }

    private func requireContrast(
        _ foreground: RGB,
        _ background: RGB,
        minimum: Double,
        _ description: String
    ) {
        let ratio = foreground.contrastRatio(with: background)
        #expect(
            ratio >= minimum,
            "\(description) is \(ratio):1; required \(minimum):1"
        )
    }
}

private struct WebPalette {
    let page: String
    let panel: String
    let accent: String
    let accentSoft: String
    let border: String
    let text: String
    let muted: String
    let code: String
    let link: String
    let focus: String

    var allHexValues: [String] {
        [page, panel, accent, accentSoft, border, text, muted, code, link, focus]
    }
}

private struct RGB {
    let red: Double
    let green: Double
    let blue: Double

    static let white = RGB(red: 1, green: 1, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: red, green: green, blue: blue)
    }

    init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    func contrastRatio(with other: RGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func linear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
