import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ghostWriter

struct WordExportThemeTests {
    @Test func omittedSettingsProduceStandardOutputStyles() throws {
        let theme = try WordExportTheme.decode(Data("{\"version\":1}".utf8))
        let standard = try MarkdownToWordConverter.convert(title: "Title", markdown: "## Heading\nText")
        let themed = try MarkdownToWordConverter.convert(title: "Title", markdown: "## Heading\nText", theme: theme)
        let paths: Set<String> = ["word/document.xml", "word/styles.xml"]
        #expect(try WordPackage.entries(from: standard, paths: paths) == WordPackage.entries(from: themed, paths: paths))
    }

    @Test func validatesExampleAndAppliesStylesAndPageGeometry() throws {
        let json = """
        {"version":1,"body":{"font":"A & B","size":12,"spaceAfter":8,"lineSpacing":1.5},"headings":{"2":{"size":20,"color":"123abc","bold":false}},"list":{"spaceAfter":4},"table":{"font":"Arial","size":10},"page":{"width":595,"height":842,"left":50,"right":50}}
        """
        let theme = try WordExportTheme.decode(Data(json.utf8))
        let data = try MarkdownToWordConverter.convert(title: "Book", markdown: "## Heading\n1. Item", theme: theme)
        let entries = try WordPackage.entries(from: data, paths: ["word/styles.xml", "word/document.xml"])
        let styles = String(decoding: try #require(entries["word/styles.xml"]), as: UTF8.self)
        let xml = String(decoding: try #require(entries["word/document.xml"]), as: UTF8.self)
        #expect(styles.contains("A &amp; B"))
        #expect(styles.contains("<w:sz w:val=\"40\"/>"))
        #expect(styles.contains("<w:color w:val=\"123ABC\"/>"))
        #expect(styles.contains("<w:b w:val=\"0\"/>"))
        #expect(styles.contains("w:line=\"360\""))
        #expect(xml.contains("w:w=\"11900\" w:h=\"16840\""))
        #expect(xml.contains("w:val=\"ListParagraph\""))
    }

    @Test func helpExampleIsAValidCompleteTheme() throws {
        let theme = try WordExportTheme.decode(Data(WordExportHelp.example.utf8))
        #expect(theme.headings?.count == 6)
        #expect(theme.body?.font == "Georgia")
        #expect(theme.page?.width == 612)
        let data = try MarkdownToWordConverter.convert(title: "Example", markdown: "## Heading\n\nText", theme: theme)
        #expect(!data.isEmpty)
    }

    @Test func themedPageFitsLargeImagesInsideMargins() throws {
        let context = try #require(CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 8000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let imageData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(imageData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let model = WordDocumentModel(blocks: [.paragraph(WordParagraph(runs: [WordRun(image: WordImage(fileName: "large.png", data: imageData as Data))]))])
        let theme = try WordExportTheme.decode(Data("{\"version\":1,\"page\":{\"width\":300,\"height\":400,\"left\":50,\"right\":50}}".utf8))
        let data = try WordprocessingMLWriter.write(title: "Image", document: model, theme: theme)
        let parts = try WordPackage.entries(from: data, paths: ["word/document.xml"])
        let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
        #expect(xml.contains("<wp:extent cx=\"2540000\" cy=\"1270000\"/>"))
    }

    @Test func rejectsInvalidThemes() {
        let values = [
            "{}", "[]", "{", "{\"version\":2}",
            "{\"version\":true}", "{\"version\":1,\"font\":\"Arial\"}",
            "{\"version\":1,\"body\":null}", "{\"version\":1,\"headings\":{\"7\":{}}}",
            "{\"version\":1,\"body\":{\"size\":0}}", "{\"version\":1,\"body\":{\"size\":\"12\"}}",
            "{\"version\":1,\"body\":{\"color\":\"#123456\"}}", "{\"version\":1,\"body\":{\"font\":\"\"}}",
            "{\"version\":1,\"body\":{\"size\":true}}", "{\"version\":1,\"body\":{\"unknown\":1}}",
            "{\"version\":1,\"body\":{\"alignment\":\"middle\"}}", "{\"version\":1,\"page\":{\"width\":144}}"
        ]
        for value in values { #expect(throws: (any Error).self) { try WordExportTheme.decode(Data(value.utf8)) } }
        #expect(throws: (any Error).self) { try WordExportTheme.decode(Data(repeating: 32, count: 65_537)) }
    }
}
