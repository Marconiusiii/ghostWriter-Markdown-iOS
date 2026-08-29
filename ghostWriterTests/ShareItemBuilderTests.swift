//
//  ShareItemBuilderTests.swift
//  ghostWriterTests
//
//  Verifies that shared files contain the promised format and that HTML is a
//  complete standalone document rather than a fragment or plain Markdown.
//

import Foundation
import LinkPresentation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import ghostWriter

struct ShareItemBuilderTests {

    @MainActor
    @Test func fileActivitySourceShowsAndDeliversTheCompleteFileName() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Produce.brf")
        let source = ShareFileActivityItemSource(fileURL: url)
        let controller = UIActivityViewController(
            activityItems: [],
            applicationActivities: nil
        )

        let metadata = try #require(
            source.activityViewControllerLinkMetadata(controller)
        )
        #expect(metadata.title == "Produce.brf")
        #expect(metadata.originalURL == nil)
        #expect(metadata.url == nil)
        #expect(
            source.activityViewController(
                controller,
                itemForActivityType: nil
            ) as? URL == url
        )
        #expect(
            source.activityViewControllerPlaceholderItem(controller) as? URL
                == url
        )
        #expect(
            source.activityViewController(
                controller,
                dataTypeIdentifierForActivityType: nil
            ) == UTType(filenameExtension: "brf")?.identifier
        )
    }

    @Test func htmlShareIsACompleteRenderedDocument() throws {
        let url = try ShareItemBuilder.makeFile(
            title: "Accessible Notes",
            markdown: "## Introduction\n\nThis is **important**.",
            format: .html
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let html = try String(contentsOf: url, encoding: .utf8)

        #expect(url.pathExtension == "html")
        #expect(UTType(filenameExtension: url.pathExtension) == .html)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<head>"))
        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(html.contains("<meta name=\"viewport\""))
        #expect(html.contains("<title>Accessible Notes</title>"))
        #expect(html.contains("<main>"))
        #expect(html.contains("<h1>Accessible Notes</h1>"))
        #expect(html.contains("<h2>Introduction</h2>"))
        #expect(html.contains("<strong>important</strong>"))
        #expect(html.contains("</main>"))
        #expect(html.contains("</html>"))
    }

    @Test func htmlShareEscapesTheDocumentTitle() throws {
        let html = ShareItemBuilder.contents(
            title: "Notes <Draft>",
            markdown: "Body",
            format: .html
        )

        #expect(html.contains("<title>Notes &lt;Draft&gt;</title>"))
        #expect(html.contains("<h1>Notes &lt;Draft&gt;</h1>"))
        #expect(!html.contains("<title>Notes <Draft></title>"))
    }

    @Test func emptyHTMLShareStillHasReadableContent() {
        let html = ShareItemBuilder.contents(
            title: "Empty Note",
            markdown: "",
            format: .html
        )

        #expect(html.contains("<h1>Empty Note</h1>"))
        #expect(html.contains("<p class=\"empty-state\">This document is empty.</p>"))
    }

    @Test func markdownFormatKeepsTheSourceVerbatim() {
        let markdown = "# Literal Markdown"

        #expect(
            ShareItemBuilder.contents(
                title: "Note",
                markdown: markdown,
                format: .markdown
            ) == markdown
        )
    }

    @Test func writtenMarkdownFileIsByteForByteUTF8Source() async throws {
        let markdown = "# Exact source 📝\n\n"
            + "Trailing spaces stay here.  \n"
            + "\tTabbed and \\*escaped\\*.\n"
            + "<u>inline HTML</u>\n"
            + "```swift\nprint(\"Hello\")\n```\n"
            + "![Tactile map](map.svg \"tactile\")\n"
            + "No final newline"

        let url = try await EditorShareFileWriter.write(
            format: .markdown,
            title: "Exact source",
            fileName: "Exact source",
            markdown: markdown,
            sourceDirectory: nil
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(try Data(contentsOf: url) == Data(markdown.utf8))
    }

    @Test func powerPointShareHasTheExpectedNameAndPackageType() async throws {
        let url = try await EditorShareFileWriter.write(
            format: .powerPoint,
            title: "Accessible deck",
            fileName: "Accessible deck",
            markdown: "# Accessible deck\n\n## First slide\n\nBody.",
            sourceDirectory: nil,
            powerPointOptions: PowerPointExportOptions(theme: .warmPaper)
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.lastPathComponent == "Accessible deck.pptx")
        #expect(UTType(filenameExtension: url.pathExtension)?.conforms(to: .data) == true)
        #expect(try Data(contentsOf: url).starts(with: [0x50, 0x4B]))
    }

    @Test func plainTextFormatStripsMarkdownSyntax() {
        // Plain text used to hand over the source verbatim, which meant hashes
        // and asterisks were read aloud as punctuation — the least readable
        // format under the name promising the most readable.
        let contents = ShareItemBuilder.contents(
            title: "Note",
            markdown: "# Literal Markdown\n\nSome **bold** text.",
            format: .plainText
        )

        #expect(contents.contains("Literal Markdown"))
        #expect(contents.contains("Some bold text."))
        #expect(!contents.contains("#"))
        #expect(!contents.contains("**"))
    }

    @Test func plainTextMatchingLevelTwoHeadingStillReceivesDocumentTitle() {
        let contents = ShareItemBuilder.contents(
            title: "Notes",
            markdown: "## Notes\n\nBody",
            format: .plainText
        )

        #expect(contents.hasPrefix("Notes\n=====\n\nNotes\n-----"))
    }

    @Test func plainTextRepresentativeDocumentRemainsReadable() {
        let markdown = """
        ## Section

        Paragraph with **bold**, [site](https://example.com), and ![Map](map.png).

        3. Third
          - [x] Nested task
        4. Fourth

        | Name | Value |
        | --- | ---: |
        | العربية | 日本語 📝 |

        > Quoted *text*.

        ```swift
        let value = 1
        ```
        """

        let contents = PlainTextWriter.write(title: "Guide", markdown: markdown)

        #expect(contents == """
        Guide
        =====

        Section
        -------

        Paragraph with bold, site (https://example.com), and [Image: Map].

        3. Third
           - Completed: Nested task
        4. Fourth

        Name     Value
        -------  -----
        العربية  日本語 📝

        > Quoted text.

        Code (swift):
            let value = 1

        """)
    }

    @Test func htmlEmbedsManagedLocalImagesAndPreservesTheirMeaning() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-html-image-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try tinyPNG.write(to: assets.appendingPathComponent("map.png"))

        let html = ShareItemBuilder.contents(
            title: "Images",
            markdown: "![Tactile map](.ghostwriter-assets-test/map.png \"tactile\")\n\n![](.ghostwriter-assets-test/map.png)",
            format: .html,
            sourceDirectory: root
        )

        #expect(html.contains("src=\"data:image/png;base64,"))
        #expect(html.contains("alt=\"\" title=\"tactile\""))
        #expect(html.contains("<figcaption>Tactile graphic: Tactile map</figcaption>"))
        #expect(html.components(separatedBy: "Tactile map").count == 2)
        #expect(html.contains("alt=\"\""))
        #expect(!html.contains(".ghostwriter-assets-test/map.png"))
    }

    @Test func unavailableLocalHTMLImageBecomesReadableFallback() {
        let html = ShareItemBuilder.contents(
            title: "Images",
            markdown: "![Missing diagram](.ghostwriter-assets-test/missing.png)",
            format: .html
        )

        #expect(html.contains("<span class=\"image-fallback\">Image: Missing diagram</span>"))
        #expect(!html.contains("<img"))
    }

    @Test func insertedTactileSVGWithInternalClipPathIsEmbeddedInHTML() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-html-tactile-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">
          <defs><clipPath id="bodyClip"><circle cx="10" cy="10" r="8"/></clipPath></defs>
          <path clip-path="url(#bodyClip)" d="M0 0h20v20z"/>
        </svg>
        """.utf8)
        try svg.write(to: assets.appendingPathComponent("hooty.svg"))

        let html = ShareItemBuilder.contents(
            title: "FrootLoops",
            markdown: "![A cute owl](.ghostwriter-assets-test/hooty.svg \"tactile\")",
            format: .html,
            sourceDirectory: root
        )

        #expect(html.contains("src=\"data:image/svg+xml;base64,"))
        #expect(html.contains("alt=\"\" title=\"tactile\""))
        #expect(html.contains("<figcaption>Tactile graphic: A cute owl</figcaption>"))
        #expect(!html.contains("image-fallback"))
    }

    @Test func unsafeTactileSVGBecomesReadableHTMLFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-html-unsafe-tactile-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>bad()</script></svg>".utf8)
            .write(to: assets.appendingPathComponent("unsafe.svg"))

        let html = ShareItemBuilder.contents(
            title: "Images",
            markdown: "![Unsafe diagram](.ghostwriter-assets-test/unsafe.svg \"tactile\")",
            format: .html,
            sourceDirectory: root
        )

        #expect(html.contains("<span class=\"image-fallback\">Tactile graphic: Unsafe diagram</span>"))
        #expect(!html.contains("data:image/svg+xml"))
    }

    private var tinyPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
    }
}
