import Foundation
import Testing
import ZIPFoundation
@testable import ghostWriter

struct ExportImageResourceTests {
    @Test func safeSelfContainedSVGIsAccepted() {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></svg>".utf8)
        let internalClipPath = Data("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><clipPath id="bodyClip"><circle cx="5" cy="5" r="4"/></clipPath></defs>
          <path clip-path="url(#bodyClip)" style="fill:url('#bodyClip')" d="M0 0h10v10z"/>
        </svg>
        """.utf8)

        #expect(ExportImageResource.isSafeSVG(svg))
        #expect(ExportImageResource.isSafeSVG(internalClipPath))
    }

    @Test func activeOrExternalSVGContentIsRejected() {
        let script = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>bad()</script></svg>".utf8)
        let external = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.com/a.png\"/></svg>".utf8)
        let externalCSS = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><path style=\"fill:url(https://example.com/fill.svg)\"/></svg>".utf8)
        let importedCSS = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><style>@import 'https://example.com/style.css';</style></svg>".utf8)
        let escapedExternalCSS = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><path style=\"fill:u\\\\72l(https://example.com/fill.svg)\"/></svg>".utf8)
        let nestedRoot = Data("<wrapper><svg xmlns=\"http://www.w3.org/2000/svg\"/></wrapper>".utf8)

        #expect(!ExportImageResource.isSafeSVG(script))
        #expect(!ExportImageResource.isSafeSVG(external))
        #expect(!ExportImageResource.isSafeSVG(externalCSS))
        #expect(!ExportImageResource.isSafeSVG(importedCSS))
        #expect(!ExportImageResource.isSafeSVG(escapedExternalCSS))
        #expect(!ExportImageResource.isSafeSVG(nestedRoot))
    }

    @Test func rasterSignaturesMustMatchTheirDeclaredFormat() {
        let png = tinyPNG
        let truncatedJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0])

        #expect(ExportImageResource.hasValidImageData(png, mediaType: "image/png"))
        #expect(!ExportImageResource.hasValidImageData(png, mediaType: "image/jpeg"))
        #expect(!ExportImageResource.hasValidImageData(truncatedJPEG, mediaType: "image/jpeg"))
        #expect(!ExportImageResource.hasValidImageData(Data([1, 2, 3]), mediaType: "image/png"))
    }

    @Test func onlyDocumentManagedAssetsArePackaged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-image-test-\(UUID().uuidString)")
        let firstDirectory = root.appendingPathComponent(".ghostwriter-assets-one")
        let secondDirectory = root.appendingPathComponent(".ghostwriter-assets-two")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try tinyPNG.write(to: firstDirectory.appendingPathComponent("photo.png"))
        try tinyPNG.write(to: secondDirectory.appendingPathComponent("photo.png"))
        try Data([7, 8, 9]).write(to: root.appendingPathComponent("private.png"))

        let markdown = """
        ![First](.ghostwriter-assets-one/photo.png)
        ![Second](.ghostwriter-assets-two/photo.png)
        ![Outside](../private.png)
        ![Absolute](/tmp/private.png)
        ![Remote](https://example.com/image.png)
        """
        let document = MarkdownDocumentParser.parse(markdown)
        let resources = EPUBWriter.collectImageResources(document, sourceDirectory: root)

        #expect(resources.images.count == 2)
        #expect(Set(resources.images.map(\.href)).count == 2)
        #expect(resources.hrefBySource["../private.png"] == nil)
        #expect(resources.hrefBySource["/tmp/private.png"] == nil)
        #expect(resources.hrefBySource["https://example.com/image.png"] == nil)
    }

    @Test func incorrectlyLabeledOrAnimatedImagesAreNotPackaged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-image-signature-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("not a png".utf8).write(to: assets.appendingPathComponent("fake.png"))
        try Data("GIF89a".utf8).write(to: assets.appendingPathComponent("animated.gif"))
        let document = MarkdownDocumentParser.parse(
            "![Fake](.ghostwriter-assets-test/fake.png)\n![Animated](.ghostwriter-assets-test/animated.gif)"
        )

        let resources = EPUBWriter.collectImageResources(document, sourceDirectory: root)
        #expect(resources.images.isEmpty)
    }

    @Test func unavailableImageBecomesAlternativeTextInsteadOfBrokenReference() throws {
        let data = try EPUBWriter.write(
            title: "Images",
            markdown: "![Remote description](https://example.com/image.png)"
        )
        let archive = try Archive(data: data, accessMode: .read)
        let entry = try #require(archive["OEBPS/content.xhtml"])
        var bytes = Data()
        _ = try archive.extract(entry) { bytes.append($0) }
        let content = String(decoding: bytes, as: UTF8.self)

        #expect(content.contains("Image: Remote description"))
        #expect(!content.contains("src=\"https://example.com/image.png\""))
    }

    private var tinyPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
    }
}
