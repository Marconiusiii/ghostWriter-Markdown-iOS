import Foundation
import Testing
import ZIPFoundation
@testable import ghostWriter

struct EPUBWriterTests {
    private func entries(
        title: String,
        markdown: String,
        sourceDirectory: URL? = nil
    ) throws -> [String: String] {
        let data = try EPUBWriter.write(
            title: title,
            markdown: markdown,
            sourceDirectory: sourceDirectory
        )
        let archive = try Archive(data: data, accessMode: .read)
        var result: [String: String] = [:]
        for entry in archive {
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            result[entry.path] = String(decoding: bytes, as: UTF8.self)
        }
        return result
    }

    @Test func navigationTargetsRemainCorrectWhenTitleHeadingIsInserted() throws {
        let package = try entries(
            title: "Book title",
            markdown: "# Chapter one\n\nText.\n\n#### Detail"
        )
        let content = try #require(package["OEBPS/content.xhtml"])
        let navigation = try #require(package["OEBPS/nav.xhtml"])

        #expect(content.contains("id=\"heading-1\">Book title"))
        #expect(content.contains("id=\"heading-2\">Chapter one"))
        #expect(content.contains("id=\"heading-3\">Detail"))
        #expect(navigation.contains("content.xhtml#heading-2"))
        #expect(navigation.contains("content.xhtml#heading-3"))
        #expect(navigation.contains("<ol>\n<li><a href=\"content.xhtml#heading-3\""))
    }

    @Test func matchingDocumentTitleDoesNotCreateDuplicateHeading() throws {
        let package = try entries(title: "Book title", markdown: "# Book title\n\nText.")
        let content = try #require(package["OEBPS/content.xhtml"])
        let navigation = try #require(package["OEBPS/nav.xhtml"])

        #expect(content.components(separatedBy: ">Book title</h1>").count - 1 == 1)
        #expect(navigation.contains("content.xhtml#heading-1"))
    }

    @Test func matchingLevelTwoHeadingStillGetsDocumentTitleHeading() throws {
        let package = try entries(title: "Book title", markdown: "## Book title\n\nText.")
        let content = try #require(package["OEBPS/content.xhtml"])

        #expect(content.contains("<h1 id=\"heading-1\">Book title</h1>"))
        #expect(content.contains("<h2 id=\"heading-2\">Book title</h2>"))
    }

    @Test func accessibilityMetadataReflectsEmbeddedImages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-epub-metadata-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try tinyPNG.write(to: assets.appendingPathComponent("image.png"))

        let package = try entries(
            title: "Images",
            markdown: "![A diagram](.ghostwriter-assets-test/image.png)",
            sourceDirectory: root
        )
        let packageDocument = try #require(package["OEBPS/content.opf"])

        #expect(packageDocument.contains("schema:accessMode\">visual"))
        #expect(packageDocument.contains("schema:accessModeSufficient\">textual"))
        #expect(packageDocument.contains("schema:accessibilityFeature\">alternativeText"))
        #expect(packageDocument.contains("alternative text for informative images"))
    }

    @Test func decorativeOnlyImageParagraphIsRetained() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-epub-decoration-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try tinyPNG.write(to: assets.appendingPathComponent("decoration.png"))

        let package = try entries(
            title: "Decoration",
            markdown: "![](.ghostwriter-assets-test/decoration.png)",
            sourceDirectory: root
        )
        let content = try #require(package["OEBPS/content.xhtml"])
        let packageDocument = try #require(package["OEBPS/content.opf"])

        #expect(content.contains("<p><img src="))
        #expect(content.contains("alt=\"\""))
        #expect(!packageDocument.contains("schema:accessibilityFeature\">alternativeText"))
    }

    private var tinyPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
    }
}
