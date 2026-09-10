import Foundation
import Testing
@testable import ghostWriter

struct WordCompilationTests {
    private func source(_ title: String, _ markdown: String, directory: URL? = nil, language: String = "en-US") -> WordCompilationSource {
        WordCompilationSource(title: title, markdown: markdown, sourceDirectory: directory, language: language)
    }

    @Test func headingsShiftOnceWithSingleTitleAndClampAtSix() throws {
        let sources = [source("First", "# First\n# Another\n##### Five\n###### Six"), source("Second", "# Second\n## Two")]
        var options = WordExportOptions()
        options.preservesHeadingStructure = false
        let model = WordCompilation.document(sources: sources, options: options)
        let paragraphs = model.blocks.compactMap { block -> WordParagraph? in
            if case .paragraph(let value) = block { return value }; return nil
        }
        #expect(paragraphs.compactMap(\.headingLevel) == [1, 2, 6, 6, 2, 3])
        #expect(paragraphs.filter(\.pageBreakBefore).count == 1)
        #expect(paragraphs.first?.pageBreakBefore == false)
        let data = try WordCompilation.write(title: "Book", sources: sources, options: options)
        let entries = try WordPackage.entries(from: data, paths: ["word/document.xml"])
        let xml = String(decoding: try #require(entries["word/document.xml"]), as: UTF8.self)
        #expect(xml.components(separatedBy: "w:val=\"Heading1\"").count - 1 == 1)
        #expect(!xml.contains("Heading7"))
        #expect(xml.components(separatedBy: "<w:pageBreakBefore/>").count - 1 == 1)
    }

    @Test func continuousOutputKeepsBlocksAndIndependentLists() throws {
        var options = WordExportOptions()
        options.startsDocumentsOnNewPages = false
        let sources = [source("First", "1. One\n2. Two"), source("Second", "1. Restart\n\n| A | B |\n| --- | --- |\n| X | Y |", language: "es-MX")]
        let data = try WordCompilation.write(title: "Book", sources: sources, options: options)
        let entries = try WordPackage.entries(from: data, paths: ["word/document.xml", "word/numbering.xml"])
        let xml = String(decoding: try #require(entries["word/document.xml"]), as: UTF8.self)
        let numbering = String(decoding: try #require(entries["word/numbering.xml"]), as: UTF8.self)
        #expect(!xml.contains("pageBreakBefore"))
        #expect(xml.contains("<w:tbl>"))
        #expect(xml.contains("<w:lang w:val=\"es-MX\"/>"))
        #expect(xml.contains("w:val=\"Heading1\""))
        #expect(numbering.components(separatedBy: "<w:num w:numId=").count - 1 == 2)
    }

    @Test func imagesResolveBesideEachSourceAndKeepDescriptions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII="))
        let directories = [root.appendingPathComponent("one"), root.appendingPathComponent("two")]
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("picture.png"))
        }
        let data = try WordCompilation.write(title: "Pictures", sources: [source("One", "![First image](picture.png)", directory: directories[0]), source("Two", "![Second image](picture.png)", directory: directories[1])], options: WordExportOptions())
        let entries = try WordPackage.entries(from: data, withPrefix: "word/media/")
        #expect(entries.count == 2)
        let parts = try WordPackage.entries(from: data, paths: ["word/document.xml"])
        let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
        #expect(xml.contains("descr=\"First image\""))
        #expect(xml.contains("descr=\"Second image\""))
    }

    @Test func emptySourcesDoNotCreateLeadingBlankPagesAndPreservationRetainsLevels() {
        let sources = [source("Empty", ""), source("Next", "## Heading")]
        let document = WordCompilation.document(sources: sources, options: WordExportOptions())
        let paragraphs = document.blocks.compactMap { if case .paragraph(let value) = $0 { return value }; return nil }
        #expect(paragraphs.compactMap(\.headingLevel) == [1, 1, 2])
        #expect(paragraphs.filter(\.pageBreakBefore).count == 1)
    }

    @Test func rejectsEmptyCompilation() {
        #expect(throws: (any Error).self) { try WordCompilation.write(title: "Empty", sources: [], options: WordExportOptions()) }
    }
}
