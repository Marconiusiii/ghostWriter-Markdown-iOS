import Foundation
import Testing
@testable import ghostWriter

struct HTMLExportStyleTests {
    @Test func bothExportPathsApplyOnlyTheSelectedStyle() async throws {
        for style in HTMLExportStyle.allCases {
            let markdown = "# Title\n\n## Chapter\n\n[Link](https://example.com)\n\n| A | B |\n|---|---|\n| One | Two |"
            let single = try await EditorShareFileWriter.write(
                format: .html, title: "Title", fileName: "Title", markdown: markdown,
                sourceDirectory: nil, includesTableOfContents: true, htmlStyle: style
            )
            defer { try? FileManager.default.removeItem(at: single.deletingLastPathComponent()) }
            var settings = CompilationExportSettings()
            settings.format = .html
            settings.htmlStyle = style
            settings.includesTableOfContents = true
            let compilation = try await CompilationFileWriter.write(
                title: "Title", sources: [WordCompilationSource(title: "Title", markdown: markdown, language: "en")], settings: settings
            )
            defer { try? FileManager.default.removeItem(at: compilation.deletingLastPathComponent()) }
            for url in [single, compilation] {
                let html = try String(contentsOf: url, encoding: .utf8)
                #expect(html.contains(HTMLTemplate.exportStylesheet(for: style)))
                #expect(!html.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.first == " " })
                #expect(html.contains("prefers-color-scheme: dark"))
                #expect(html.contains("<main>"))
                #expect(html.contains("name=\"viewport\""))
                #expect(html.contains("<details><summary><h2>Table of Contents</h2></summary>"))
                #expect(html.contains("href=\"#heading-2\""))
                #expect(!html.contains("href=\"style.css\""))
                if style == .ghostWriter {
                    #expect(html.contains("class=\"table-scroll\" tabindex=\"0\""))
                }
            }
        }
    }

    @Test func standardIsTheDefaultAndThemeSupportsReaderPreferences() {
        #expect(CompilationExportSettings().htmlStyle == .standard)
        let standard = HTMLTemplate.exportDocument(title: "Title", body: "<p>Text</p>")
        #expect(standard.contains(HTMLTemplate.exportStylesheet(for: .standard)))
        let css = HTMLTemplate.exportStylesheet(for: .ghostWriter)
        #expect(css.contains("font-size: 100%"))
        #expect(css.contains("@media (prefers-color-scheme: dark)"))
        #expect(css.contains("@media (forced-colors: active)"))
        #expect(css.contains("@media print"))
        #expect(css.contains(":focus-visible"))
        #expect(css.contains("text-decoration: underline"))
    }

    @Test(arguments: HTMLExportStyle.allCases)
    func exportColorsAreAtTheTopAndIndentationUsesTabs(style: HTMLExportStyle) throws {
        let css = HTMLTemplate.exportStylesheet(for: style)
        let sections = css.components(separatedBy: "/* Document */")
        #expect(sections.count == 2)
        #expect(sections[0].hasPrefix("/* Colors */\n:root {"))
        #expect(sections[0].contains("@media (prefers-color-scheme: dark)"))
        #expect(!sections[1].contains(":root"))
        #expect(!sections[1].contains("#"))
        for style in HTMLExportStyle.allCases {
            let output = HTMLTemplate.exportStylesheet(for: style)
            #expect(output.contains("\n\t"))
            #expect(!output.split(separator: "\n").contains { $0.first == " " })
        }
        let body = "<pre><code>    keep these four spaces\n\tkeep this tab</code></pre>"
        let html = HTMLTemplate.exportDocument(title: "Code", style: style, body: body)
        #expect(html.contains(body))
    }

    @Test(arguments: HTMLExportStyle.allCases)
    func themePaletteMeetsContrastMinimums(style: HTMLExportStyle) throws {
        let css = HTMLTemplate.exportStylesheet(for: style)
        func palette(_ dark: Bool) throws -> [String: String] {
            // Read actual exported declarations in order, including dark overrides.
            let expression = try NSRegularExpression(pattern: #"--([a-z-]+):\s*(#[a-fA-F0-9]{6})"#)
            let light = css.components(separatedBy: "@media (prefers-color-scheme: dark)")[0]
            var result: [String: String] = [:]
            func apply(_ source: String) {
                for m in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                    let key = String(source[Range(m.range(at: 1), in: source)!])
                    result[key] = String(source[Range(m.range(at: 2), in: source)!])
                }
            }
            apply(light)
            if dark {
                for block in css.components(separatedBy: "@media (prefers-color-scheme: dark)").dropFirst() {
                    apply(String(block.prefix { $0 != "}" }))
                }
            }
            return result
        }
        func luminance(_ hex: String) -> Double {
            let value = Int(hex.dropFirst(), radix: 16)!
            let channels = [16, 8, 0].map { shift -> Double in
                let c = Double((value >> shift) & 255) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        func contrast(_ a: String, _ b: String) -> Double {
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for dark in [false, true] {
            let colors = try palette(dark)
            for background in ["page-background", "code-background", "table-header-background"] {
                for foreground in ["text-color", "secondary-text-color", "heading-color", "link-color"] {
                    #expect(contrast(try #require(colors[foreground]), try #require(colors[background])) >= 4.5)
                }
                #expect(contrast(try #require(colors["border-color"]), try #require(colors[background])) >= 3)
                #expect(contrast(try #require(colors["focus-color"]), try #require(colors[background])) >= 3)
            }
        }
    }
}
