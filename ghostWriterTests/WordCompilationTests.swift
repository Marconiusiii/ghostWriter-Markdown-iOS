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
        let model = try WordCompilation.document(sources: sources, options: options)
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

    @Test func existingOpeningTitlesReplaceFilenameHeadings() throws {
        let sources = [source("title", "# My Fabulous Book\nBy the author"), source("001-chapter", "# Chapter 1\n## Beginning\nBody")]
        for preserve in [true, false] {
            var options = WordExportOptions()
            options.preservesHeadingStructure = preserve
            let model = try WordCompilation.document(sources: sources, options: options)
            let paragraphs = model.blocks.compactMap { if case .paragraph(let value) = $0 { return value }; return nil }
            #expect(paragraphs.compactMap(\.headingLevel) == (preserve ? [1, 1, 2] : [1, 2, 3]))
            #expect(paragraphs.filter(\.pageBreakBefore).count == 1)
            let data = try WordCompilation.write(title: "Book", sources: sources, options: options)
            let entries = try WordPackage.entries(from: data, paths: ["word/document.xml"])
            let xml = String(decoding: try #require(entries["word/document.xml"]), as: UTF8.self)
            #expect(xml.contains(">My Fabulous Book</w:t>"))
            #expect(xml.contains(">Chapter 1</w:t>"))
            #expect(!xml.contains(">title</w:t>"))
            #expect(!xml.contains(">001-chapter</w:t>"))
        }
    }

    @Test func missingOpeningTitleUsesFilenameWithoutReplacingLaterHeadings() throws {
        let sources = [source("Introduction", "Body before a heading\n# Later heading")]
        let data = try WordCompilation.write(title: "Book", sources: sources, options: WordExportOptions())
        let entries = try WordPackage.entries(from: data, paths: ["word/document.xml"])
        let xml = String(decoding: try #require(entries["word/document.xml"]), as: UTF8.self)
        #expect(xml.contains(">Introduction</w:t>"))
        #expect(xml.contains(">Later heading</w:t>"))
        #expect(!xml.contains("pageBreakBefore"))
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

    @Test func emptySourcesDoNotCreateLeadingBlankPagesAndPreservationRetainsLevels() throws {
        let sources = [source("Empty", ""), source("Next", "## Heading")]
        let document = try WordCompilation.document(sources: sources, options: WordExportOptions())
        let paragraphs = document.blocks.compactMap { if case .paragraph(let value) = $0 { return value }; return nil }
        #expect(paragraphs.compactMap(\.headingLevel) == [1, 1, 2])
        #expect(paragraphs.filter(\.pageBreakBefore).count == 1)
    }

    @Test func continuousBoundariesUseRealEmptyParagraphsWithoutDuplicatingExistingOnes() throws {
        for (ending, opening, expectedBlanks) in [("Tail", "# Next", 1), ("Tail\n\n", "# Next", 1), ("Tail", "\n# Next", 1), ("Tail\n\n\n", "\n# Next", 3)] {
            var options = WordExportOptions()
            options.startsDocumentsOnNewPages = false
            options.preservesHeadingStructure = false
            let model = try WordCompilation.document(sources: [source("First", "# First\n" + ending), source("filename", opening)], options: options)
            let paragraphs = model.blocks.compactMap { if case .paragraph(let p) = $0 { return p }; return nil }
            let texts = paragraphs.map { $0.runs.map(\.text).joined() }
            let tail = try #require(texts.firstIndex(of: "Tail"))
            let next = try #require(texts.firstIndex(of: "Next"))
            #expect(next - tail - 1 == expectedBlanks)
            #expect(paragraphs[(tail + 1)..<next].allSatisfy { $0.runs.isEmpty && $0.headingLevel == nil })
            #expect(paragraphs[next].headingLevel == 2)
            #expect(!paragraphs.contains { $0.pageBreakBefore })
            #expect(!texts.contains("filename"))
            let data = try WordCompilation.write(title: "Book", sources: [source("First", "# First\n" + ending), source("filename", opening)], options: options)
            let parts = try WordPackage.entries(from: data, paths: ["word/document.xml"])
            let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
            #expect(xml.contains("<w:p></w:p><w:p><w:pPr><w:pStyle w:val=\"Heading2\"/>"))
        }
    }

    @Test func leadingBlankParagraphsPreserveTheFirstTitleAndPageBreakBehavior() throws {
        let sources = [source("filename", "\n\n# Actual title\n###### Six"), source("other", "\n# Next")]
        var options = WordExportOptions()
        options.preservesHeadingStructure = false
        let model = try WordCompilation.document(sources: sources, options: options)
        let paragraphs = model.blocks.compactMap { if case .paragraph(let p) = $0 { return p }; return nil }
        #expect(paragraphs.prefix(2).allSatisfy { $0.runs.isEmpty })
        #expect(paragraphs.compactMap(\.headingLevel) == [1, 6, 2])
        #expect(paragraphs.filter(\.pageBreakBefore).count == 1)
        #expect(paragraphs.count == 6)
    }

    @Test func conversionAndZipCompressionCanStopMidOperation() throws {
        var parsingChecks = 0
        #expect(throws: CancellationError.self) {
            _ = try MarkdownToWordConverter.document(from: String(repeating: "Text\n\n", count: 2000), checkCancellation: {
                parsingChecks += 1
                if parsingChecks == 6500 { throw CancellationError() }
            })
        }
        #expect(parsingChecks == 6500)
        var packagingChecks = 0
        #expect(throws: CancellationError.self) {
            _ = try WordPackage.create(entries: ["large.xml": Data(repeating: 65, count: 2_000_000)], checkCancellation: {
                packagingChecks += 1
                if packagingChecks == 4 { throw CancellationError() }
            })
        }
        #expect(packagingChecks == 4)
    }

    @Test func cancelledTaskDoesNotProduceACompilation() async {
        let task = Task.detached { () throws -> Data in
            withUnsafeCurrentTask { $0?.cancel() }
            return try WordCompilation.write(title: "Cancelled", sources: [WordCompilationSource(title: "One", markdown: "# One", language: "en-US")], options: WordExportOptions())
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled export produced a file")
        } catch is CancellationError { }
        catch { Issue.record("Unexpected cancellation error: \(error)") }
    }

    @Test func largerContinuousCompilationKeepsThemeTablesListsImagesAndHeadingSix() throws {
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII="))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try png.write(to: directory.appendingPathComponent("image.png"))
        let body = String(repeating: "A paragraph of book text.\n\n", count: 100)
        let sources = (1...50).map { source("file-\($0)", "# Chapter \($0)\n" + body + "###### Detail\n1. Item\n\n| A | B |\n| --- | --- |\n| X | Y |\n\n![Description](image.png)", directory: directory) }
        var options = WordExportOptions()
        options.startsDocumentsOnNewPages = false
        options.preservesHeadingStructure = false
        options.theme = try WordExportTheme.decode(Data(#"{"version":1,"body":{"font":"Georgia"},"headings":{"2":{"color":"123456"}}}"#.utf8))
        let data = try WordCompilation.write(title: "Book", sources: sources, options: options)
        let parts = try WordPackage.entries(from: data, paths: ["word/document.xml", "word/styles.xml", "word/numbering.xml"])
        let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
        let styles = String(decoding: try #require(parts["word/styles.xml"]), as: UTF8.self)
        #expect(xml.components(separatedBy: "w:val=\"Heading1\"").count - 1 == 1)
        #expect(xml.components(separatedBy: "w:val=\"Heading2\"").count - 1 == 49)
        #expect(xml.components(separatedBy: "w:val=\"Heading6\"").count - 1 == 50)
        #expect(xml.components(separatedBy: "<w:tbl>").count - 1 == 50)
        #expect(xml.components(separatedBy: "<w:drawing>").count - 1 == 50)
        #expect(xml.components(separatedBy: "<w:numPr>").count - 1 == 50)
        #expect(!xml.contains("pageBreakBefore"))
        #expect(styles.contains("Georgia") && styles.contains("123456"))
    }

    @Test func rejectsEmptyCompilation() {
        #expect(throws: (any Error).self) { try WordCompilation.write(title: "Empty", sources: [], options: WordExportOptions()) }
    }
}
