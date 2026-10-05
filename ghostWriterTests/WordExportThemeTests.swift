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

    private func parts(_ theme: String, blocks: [WordBlock], title: String = "Export title") throws -> [String: String] {
        let data = try WordprocessingMLWriter.write(
            title: title, document: WordDocumentModel(blocks: blocks),
            theme: WordExportTheme.decode(Data(theme.utf8)), exportDate: Date(timeIntervalSince1970: 0)
        )
        return try WordPackage.entries(from: data, paths: ["word/document.xml", "word/styles.xml", "word/header.xml", "word/footer.xml", "docProps/core.xml"])
            .mapValues { String(decoding: $0, as: UTF8.self) }
    }

    private func paragraph(_ text: String, in xml: String) throws -> String {
        try #require(xml.components(separatedBy: "</w:p>").first { $0.contains(">\(text)</w:t>") })
    }

    @Test func firstBodyParagraphOverrideSkipsBlanksAndEndsAfterFirstParagraph() throws {
        let output = try parts(#"{"version":1,"body":{"firstLineIndent":24},"paragraphAfterHeading":{"headingLevels":[1,2],"firstLineIndent":0}}"#, blocks: [
            .paragraph(WordParagraph(runs: [WordRun(text: "Chapter")], headingLevel: 1)),
            .paragraph(WordParagraph()),
            .paragraph(WordParagraph(runs: [WordRun(text: "First")])),
            .paragraph(WordParagraph(runs: [WordRun(text: "Second")])),
            .paragraph(WordParagraph(runs: [WordRun(text: "Subsection")], headingLevel: 3)),
            .paragraph(WordParagraph(runs: [WordRun(text: "Third")]))
        ])
        let xml = try #require(output["word/document.xml"])
        #expect(try paragraph("First", in: xml).contains("w:firstLine=\"0\""))
        #expect(try !paragraph("Second", in: xml).contains("w:firstLine"))
        #expect(try !paragraph("Third", in: xml).contains("w:firstLine"))
        #expect(output["word/styles.xml"]?.contains("w:firstLine=\"480\"") == true)
        #expect(xml.contains("w:val=\"Heading1\""))
    }

    @Test func interveningBlocksAndSourceBoundariesEndIndentRule() throws {
        let interruptions: [WordBlock] = [
            .paragraph(WordParagraph(runs: [WordRun(text: "List")], list: WordListReference(level: 0, kind: .bullet))),
            .paragraph(WordParagraph(runs: [WordRun(text: "Quote")], isBlockQuote: true)),
            .paragraph(WordParagraph(runs: [WordRun(text: "Code")], isCodeBlock: true)),
            .paragraph(WordParagraph(isThematicSeparator: true)),
            .paragraph(WordParagraph(runs: [WordRun(image: WordImage(fileName: "missing.png"))])),
            .paragraph(WordParagraph(startsSourceDocument: true)),
            .table(WordTable(rows: [WordTableRow(cells: [[.paragraph(WordParagraph(runs: [WordRun(text: "Cell")]))]])]))
        ]
        for interruption in interruptions {
            let output = try parts(#"{"version":1,"paragraphAfterHeading":{"headingLevels":[1],"firstLineIndent":0}}"#, blocks: [
                .paragraph(WordParagraph(runs: [WordRun(text: "Heading")], headingLevel: 1)), interruption,
                .paragraph(WordParagraph(runs: [WordRun(text: "Following")]))
            ])
            #expect(output["word/document.xml"]?.contains("w:firstLine") == false)
        }
    }

    @Test func paragraphPaginationSupportsExplicitOverrides() throws {
        let output = try parts(#"{"version":1,"body":{"widowControl":true,"keepLinesTogether":true},"headings":{"2":{"widowControl":false,"keepLinesTogether":false,"keepWithNext":true}}}"#, blocks: [])
        let styles = try #require(output["word/styles.xml"])
        let normal = try #require(styles.components(separatedBy: "</w:style>").first { $0.contains("w:styleId=\"Normal\"") })
        let heading = try #require(styles.components(separatedBy: "</w:style>").first { $0.contains("w:styleId=\"Heading2\"") })
        #expect(normal.contains("<w:widowControl w:val=\"1\"/>"))
        #expect(normal.contains("<w:keepLines w:val=\"1\"/>"))
        #expect(heading.contains("<w:widowControl w:val=\"0\"/>"))
        #expect(heading.contains("<w:keepLines w:val=\"0\"/>"))
        #expect(heading.contains("<w:keepNext w:val=\"1\"/>"))
    }

    @Test func templatesEscapeMetadataAndUseNativeHeadingAndPageFields() throws {
        let output = try parts(#"{"version":1,"metadata":{"title":"A & B","subtitle":"<Subtitle>","author":"{{pageNumber}}"},"header":{"template":"{{title}} / {{subtitle}} / {{author}} / {{date}}"},"footer":{"template":"{{heading1}} / {{heading2}} / {{pageNumber}}"}}"#, blocks: [
            .paragraph(WordParagraph(runs: [WordRun(text: "Chapter & one")], headingLevel: 1)),
            .paragraph(WordParagraph(runs: [WordRun(text: "Section")], headingLevel: 2)),
            .paragraph(WordParagraph(runs: [WordRun(text: "Chapter two")], headingLevel: 1))
        ])
        let header = try #require(output["word/header.xml"])
        let footer = try #require(output["word/footer.xml"])
        #expect(header.contains("A &amp; B"))
        #expect(header.contains("&lt;Subtitle&gt;"))
        #expect(header.contains("{{pageNumber}}"))
        #expect(!header.contains("fldSimple"))
        #expect(header.contains("1970-01-01"))
        #expect(footer.contains("STYLEREF &quot;heading 1&quot;"))
        #expect(footer.contains("STYLEREF &quot;heading 2&quot;"))
        #expect(footer.contains("w:instr=\" PAGE \""))
        #expect(footer.contains("Chapter &amp; one"))
        #expect(output["docProps/core.xml"]?.contains("<dc:title>A &amp; B</dc:title>") == true)
    }

    @Test func missingMetadataAndHeadingLevelsHaveDefinedFallbacks() throws {
        let output = try parts(#"{"version":1,"header":{"template":"{{title}}|{{subtitle}}|{{author}}|{{heading2}}"},"footer":{"text":"{{title}} ","pageNumber":true}}"#, blocks: [])
        let header = try #require(output["word/header.xml"])
        #expect(header.contains("Export title"))
        #expect(!header.contains("STYLEREF"))
        #expect(!header.contains("ghostWriter"))
        #expect(output["word/footer.xml"]?.contains("{{title}} ") == true)
        #expect(output["word/footer.xml"]?.contains("w:instr=\" PAGE \"") == true)
    }

    @Test func rejectsInvalidAdvancedSettingsBeforeExport() {
        let fragments = [
            #""paragraphAfterHeading":{"headingLevels":[],"firstLineIndent":0}"#,
            #""paragraphAfterHeading":{"headingLevels":[1,1],"firstLineIndent":0}"#,
            #""paragraphAfterHeading":{"headingLevels":[7],"firstLineIndent":0}"#,
            #""paragraphAfterHeading":{"headingLevels":[1],"firstLineIndent":-1}"#,
            #""body":{"widowControl":"true"}"#,
            #""body":{"keepLinesTogether":1}"#,
            #""metadata":{"author":null}"#,
            #""metadata":{"author":"Line\nbreak"}"#,
            #""header":{"template":"{{Title}}"}"#,
            #""header":{"template":"{{unknown}}"}"#,
            #""header":{"template":"{{title}"}"#,
            #""header":{"template":"title}}"}"#,
            #""header":{"template":"{{title}}","text":"Title"}"#,
            #""footer":{"template":"{{pageNumber}}","pageNumber":false}"#
        ]
        for fragment in fragments {
            #expect(throws: (any Error).self) { try WordExportTheme.decode(Data(("{\"version\":1," + fragment + "}").utf8)) }
        }
    }
}
