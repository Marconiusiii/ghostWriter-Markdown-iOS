import Foundation
import Testing
import ZIPFoundation
@testable import ghostWriter

struct ExportImageResourceTests {
    @Test func safeSelfContainedSVGIsAccepted() {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></svg>".utf8)

        #expect(EPUBWriter.isSafeSVG(svg))
    }

    @Test func activeOrExternalSVGContentIsRejected() {
        let script = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>bad()</script></svg>".utf8)
        let external = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.com/a.png\"/></svg>".utf8)

        #expect(!EPUBWriter.isSafeSVG(script))
        #expect(!EPUBWriter.isSafeSVG(external))
    }

    @Test func rasterSignaturesMustMatchTheirDeclaredFormat() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])

        #expect(EPUBWriter.hasValidImageSignature(png, mediaType: "image/png"))
        #expect(EPUBWriter.hasValidImageSignature(jpeg, mediaType: "image/jpeg"))
        #expect(!EPUBWriter.hasValidImageSignature(Data([1, 2, 3]), mediaType: "image/png"))
    }

    @Test func onlyDocumentManagedAssetsArePackaged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-image-test-\(UUID().uuidString)")
        let firstDirectory = root.appendingPathComponent(".ghostwriter-assets-one")
        let secondDirectory = root.appendingPathComponent(".ghostwriter-assets-two")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([1, 2, 3]).write(to: firstDirectory.appendingPathComponent("photo.png"))
        try Data([4, 5, 6]).write(to: secondDirectory.appendingPathComponent("photo.png"))
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
}
