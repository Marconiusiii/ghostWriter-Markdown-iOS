import Foundation
import Testing
@testable import ghostWriter

struct PowerPointImportTests {
    private let assets = ".ghostwriter-assets-import-test"
    private let relPrefix = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

    private func relations(_ values: [(String, String, String, Bool)]) -> String {
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + values.map { id, type, target, external in
                "<Relationship Id=\"\(id)\" Type=\"\(relPrefix)\(type)\" Target=\"\(target)\"\(external ? " TargetMode=\"External\"" : "")/>"
            }.joined() + "</Relationships>"
    }

    private func slide(_ shapes: String, hidden: Bool = false) -> String {
        "<p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" show=\"\(hidden ? 0 : 1)\"><p:cSld><p:spTree>\(shapes)</p:spTree></p:cSld></p:sld>"
    }

    private func shape(_ text: String, type: String? = nil, id: Int = 2, paragraphs: String? = nil) -> String {
        let placeholder = type.map { "<p:ph type=\"\($0)\" idx=\"\(id)\"/>" } ?? ""
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Shape\"/><p:cNvSpPr/><p:nvPr>\(placeholder)</p:nvPr></p:nvSpPr><p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs ?? "<a:p><a:r><a:t>\(text)</a:t></a:r></a:p>")</p:txBody></p:sp>"
    }

    private func package(_ slides: [String], order: [Int]? = nil, extras: [String: Data] = [:]) throws -> Data {
        var entries = extras
        entries["_rels/.rels"] = Data(relations([("office", "officeDocument", "ppt/presentation.xml", false)]).utf8)
        let ids = (order ?? Array(slides.indices)).map { "<p:sldId id=\"\(256 + $0)\" r:id=\"r\($0)\"/>" }.joined()
        entries["ppt/presentation.xml"] = Data("<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><p:sldIdLst>\(ids)</p:sldIdLst></p:presentation>".utf8)
        entries["ppt/_rels/presentation.xml.rels"] = Data(relations(slides.indices.map { ("r\($0)", "slide", "slides/slide\($0 + 1).xml", false) }).utf8)
        for (index, xml) in slides.enumerated() { entries["ppt/slides/slide\(index + 1).xml"] = Data(xml.utf8) }
        return try PowerPointPackage.create(entries: entries)
    }

    private func convert(_ data: Data, options: PowerPointImportOptions = PowerPointImportOptions()) throws -> MarkdownDocumentImport {
        try PowerPointToMarkdownConverter.importDocument(data: data, options: options, assetDirectoryName: assets)
    }

    @Test func ghostWriterSlidesListsTablesAndNotesRoundTripWithoutExtraTitleSlide() throws {
        let source = "# Owls\n\nIntroduction\n\n## Food\n\n3. Mice\n    - Small mice\n4. Insects\n\n| Name | Count |\n| --- | --- |\n| Barn owl | 2 |\n\n***\n\nSpeak slowly\n\n## Habitat\n\nTrees"
        let original = try PowerPointWriter.write(title: "Deck", markdown: source, theme: .warmPaper)
        let imported = try convert(original)
        #expect(imported.markdown.hasPrefix("# **Owls**\n"))
        #expect(imported.markdown.contains("## **Food**"))
        #expect(imported.markdown.contains("3. Mice\n    - Small mice\n4. Insects"))
        #expect(imported.markdown.contains("| Barn owl | 2 |"))
        #expect(imported.markdown.contains("***\n\nSpeak slowly"))
        let exported = try PowerPointWriter.write(title: "Deck", markdown: imported.markdown, theme: .warmPaper)
        let originalXML = try PowerPointImportPackage(data: original).xml(at: "ppt/presentation.xml")
        let exportedXML = try PowerPointImportPackage(data: exported).xml(at: "ppt/presentation.xml")
        #expect(originalXML.descendants("sldId").count == exportedXML.descendants("sldId").count)
    }

    @Test func slideListOrderAndRepeatedTitlesArePreserved() throws {
        let data = try package([slide(shape("Same", type: "title") + shape("First")), slide(shape("Same", type: "title") + shape("Second"))], order: [1, 0])
        let text = try convert(data).markdown
        #expect(text.components(separatedBy: "## Same").count == 3)
        #expect(try #require(text.range(of: "Second")).lowerBound < #require(text.range(of: "First")).lowerBound)
    }

    @Test func hiddenSlidesAndUntitledSlideNumbersFollowOptions() throws {
        let data = try package([slide(shape("Hidden"), hidden: true), slide(shape("Visible"))])
        let visible = try convert(data).markdown
        #expect(visible.hasPrefix("## Slide 2"))
        #expect(!visible.contains("Hidden"))
        var options = PowerPointImportOptions()
        options.hiddenSlides = true
        #expect(try convert(data, options: options).markdown.contains("Hidden"))
        #expect(throws: PowerPointImportError.self) { try convert(package([slide("", hidden: true)])) }
    }

    @Test func filteringBodyAndNotesLeavesSlideHeadings() throws {
        let data = try PowerPointWriter.write(title: "Deck", markdown: "# Title\n\nIntro\n\n## Topic\n\nBody\n\n***\n\nNotes", theme: .midnight)
        var options = PowerPointImportOptions()
        options.slideText = false
        let notesOnly = try convert(data, options: options).markdown
        #expect(notesOnly.contains("## **Topic**"))
        #expect(notesOnly.contains("Notes"))
        #expect(!notesOnly.contains("Body"))
        #expect(!notesOnly.contains("Intro"))
        options.speakerNotes = false
        let headings = try convert(data, options: options).markdown
        #expect(!headings.contains("Notes"))
        #expect(!headings.contains("***"))
    }

    @Test func linksAndFormattingCanBeDisabledIndependently() throws {
        let paragraphs = "<a:p><a:r><a:rPr b=\"1\" i=\"1\" u=\"sng\" strike=\"sngStrike\"><a:hlinkClick r:id=\"web\"/></a:rPr><a:t>Words</a:t></a:r></a:p>"
        let data = try package([slide(shape("Title", type: "title") + shape("", paragraphs: paragraphs))], extras: ["ppt/slides/_rels/slide1.xml.rels": Data(relations([("web", "hyperlink", "https://example.com", true)]).utf8)])
        let formatted = try convert(data).markdown
        #expect(formatted.contains("https://example.com"))
        #expect(formatted.contains("<u>"))
        var options = PowerPointImportOptions()
        options.textFormatting = false
        #expect(try convert(data, options: options).markdown.contains("[Words](https://example.com)"))
        options.links = false
        let plain = try convert(data, options: options).markdown
        #expect(plain.contains("Words"))
        #expect(!plain.contains("https://"))
        #expect(!plain.contains("<u>"))
    }

    @Test func unsafeLinksBecomeText() throws {
        let paragraphs = "<a:p><a:r><a:rPr><a:hlinkClick r:id=\"bad\"/></a:rPr><a:t>Click</a:t></a:r></a:p>"
        let data = try package([slide(shape("", paragraphs: paragraphs))], extras: ["ppt/slides/_rels/slide1.xml.rels": Data(relations([("bad", "hyperlink", "javascript:alert(1)", true)]).utf8)])
        let text = try convert(data).markdown
        #expect(text.contains("Click"))
        #expect(!text.contains("javascript"))
    }

    @Test func groupedShapesKeepStoredOrderInsteadOfCoordinateSorting() throws {
        let data = try package([slide("<p:grpSp>" + shape("Second visually", id: 4) + shape("First visually", id: 5) + "</p:grpSp>")])
        let text = try convert(data).markdown
        #expect(try #require(text.range(of: "Second visually")).lowerBound < #require(text.range(of: "First visually")).lowerBound)
    }

    @Test func inheritedMasterListFormattingAndNumberingAreRetained() throws {
        let paragraphs = "<a:p><a:r><a:t>First</a:t></a:r></a:p><a:p><a:r><a:t>Second</a:t></a:r></a:p><a:p><a:pPr lvl=\"1\"/><a:r><a:t>Nested</a:t></a:r></a:p>"
        let layout = slide(shape("", type: "body", id: 4)).replacingOccurrences(of: "p:sld", with: "p:sldLayout")
        let master = "<p:sldMaster xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><p:cSld><p:spTree/></p:cSld><p:txStyles><p:bodyStyle><a:lvl1pPr><a:buAutoNum type=\"arabicPeriod\" startAt=\"3\"/><a:defRPr b=\"1\"/></a:lvl1pPr><a:lvl2pPr><a:buChar char=\"-\"/></a:lvl2pPr></p:bodyStyle></p:txStyles></p:sldMaster>"
        let data = try package([slide(shape("", type: "body", id: 4, paragraphs: paragraphs))], extras: [
            "ppt/slides/_rels/slide1.xml.rels": Data(relations([("layout", "slideLayout", "../slideLayouts/layout.xml", false)]).utf8),
            "ppt/slideLayouts/layout.xml": Data(layout.utf8),
            "ppt/slideLayouts/_rels/layout.xml.rels": Data(relations([("master", "slideMaster", "../slideMasters/master.xml", false)]).utf8),
            "ppt/slideMasters/master.xml": Data(master.utf8)
        ])
        let text = try convert(data).markdown
        #expect(text.contains("3. **First**"))
        #expect(text.contains("4. **Second**"))
        #expect(text.contains("    - Nested"))
    }

    @Test func tableFilteringDoesNotDependOnSlideText() throws {
        let data = try PowerPointWriter.write(title: "Deck", markdown: "## Table\n\n| A | B |\n| --- | --- |\n| One | Two |", theme: .warmPaper)
        var options = PowerPointImportOptions()
        options.slideText = false
        #expect(try convert(data, options: options).markdown.contains("| One | Two |"))
        options.tables = false
        #expect(try !convert(data, options: options).markdown.contains("One"))
    }

    @Test func mergedTablesUseLabeledRowsAndGiveANotice() throws {
        let table = "<p:graphicFrame><a:graphic><a:graphicData><a:tbl><a:tr><a:tc gridSpan=\"2\"><a:txBody><a:p><a:r><a:t>Merged</a:t></a:r></a:p></a:txBody></a:tc></a:tr></a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
        let result = try convert(package([slide(table)]))
        #expect(result.markdown.contains("Row 1, column 1: Merged"))
        #expect(result.notices.contains { $0.contains("merged") })
    }

    private func picture(_ id: String = "image", decorative: Bool = false, description: String = "An owl") -> String {
        "<p:pic><p:nvPicPr><p:cNvPr id=\"8\" name=\"Picture\" descr=\"\(description)\">\(decorative ? "<a:extLst><a:ext><a:decorative val=\"1\"/></a:ext></a:extLst>" : "")</p:cNvPr></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(id)\"/></p:blipFill></p:pic>"
    }

    @Test func imagesUseSafeRelativePathsPreserveAltAndDeduplicateAssets() throws {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>".utf8)
        let data = try package([slide(picture() + picture())], extras: [
            "ppt/slides/_rels/slide1.xml.rels": Data(relations([("image", "image", "../media/strange name.svg", false)]).utf8),
            "ppt/media/strange name.svg": svg
        ])
        let result = try convert(data)
        #expect(result.assets.count == 1)
        #expect(result.assets.first?.fileName == "image-1.svg")
        #expect(result.markdown.contains("![An owl](\(assets)/image-1.svg)"))
        var options = PowerPointImportOptions()
        options.images = false
        let without = try convert(data, options: options)
        #expect(without.assets.isEmpty)
        #expect(!without.markdown.contains("An owl"))
    }

    @Test func decorativeAndMissingImageDescriptionsAreHandledSeparately() throws {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        let data = try package([slide(picture(decorative: true) + picture(description: ""))], extras: [
            "ppt/slides/_rels/slide1.xml.rels": Data(relations([("image", "image", "../media/owl.svg", false)]).utf8), "ppt/media/owl.svg": svg
        ])
        var options = PowerPointImportOptions()
        let normal = try convert(data)
        #expect(normal.imagesNeedingAlternativeText == 1)
        #expect(normal.markdown.components(separatedBy: "![]").count == 2)
        options.decorativeImages = true
        let all = try convert(data, options: options)
        #expect(all.imagesNeedingAlternativeText == 1)
        #expect(all.markdown.components(separatedBy: "![]").count == 3)
    }

    @Test func externalAndUnsafeImagesDoNotAbortThePresentation() throws {
        for (target, external) in [("https://example.com/owl.png", true), ("../../../outside.svg", false), ("../media/bad.svg", false)] {
            let data = try package([slide(picture() + shape("Keep this text"))], extras: [
                "ppt/slides/_rels/slide1.xml.rels": Data(relations([("image", "image", target, external)]).utf8),
                "ppt/media/bad.svg": Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>".utf8)
            ])
            let result = try convert(data)
            #expect(result.assets.isEmpty)
            #expect(result.markdown.contains("Image: An owl"))
            #expect(result.markdown.contains("Keep this text"))
            #expect(!result.notices.isEmpty)
        }
    }

    @Test func optionalFooterDateAndSlideNumberContentIsExcludedByDefault() throws {
        let data = try package([slide(shape("Footer", type: "ftr") + shape("Today", type: "dt", id: 3) + shape("42", type: "sldNum", id: 4))])
        #expect(try convert(data).markdown == "## Slide 1\n")
        var options = PowerPointImportOptions()
        options.footers = true; options.dates = true; options.slideNumbers = true
        let text = try convert(data, options: options).markdown
        #expect(text.contains("Footer"))
        #expect(text.contains("Today"))
        #expect(text.contains("42"))
    }

    @Test func malformedEncryptedAndUnsafeXMLAreRejected() throws {
        #expect(throws: PowerPointImportError.self) { try convert(Data("broken".utf8)) }
        #expect(throws: PowerPointImportError.self) { try convert(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) }
        for xml in ["<p:sld>", "<!DOCTYPE root [<!ENTITY read SYSTEM 'file:///etc/passwd'>]><root>&read;</root>", String(repeating: "<a>", count: 70) + String(repeating: "</a>", count: 70)] {
            #expect(throws: PowerPointImportError.self) { try convert(package([xml])) }
        }
    }

    @Test func packageTraversalAndOversizedPartsAreRejected() throws {
        for target in ["../../outside.xml", "file:///tmp/read.xml", "%2e%2e/%2e%2e/read.xml", "//example.com/slide.xml"] {
            #expect(throws: PowerPointImportError.self) { try PowerPointImportPackage.resolve(target, relativeTo: "ppt/presentation.xml") }
        }
        let data = try PowerPointPackage.create(entries: ["large.xml": Data(repeating: 65, count: 1025)])
        let package = try PowerPointImportPackage(data: data)
        #expect(throws: PowerPointImportError.self) { try package.data(at: "large.xml", limit: 1024) }
    }

    @Test func missingSlideIsFatalButMissingNotesProduceANotice() throws {
        let missing = try package([slide(shape("Body"))], order: [1])
        #expect(throws: PowerPointImportError.self) { try convert(missing) }
        let notes = try package([slide(shape("Body"))], extras: ["ppt/slides/_rels/slide1.xml.rels": Data(relations([("notes", "notesSlide", "../notesSlides/missing.xml", false)]).utf8)])
        let result = try convert(notes)
        #expect(result.markdown.contains("Body"))
        #expect(result.notices.contains { $0.contains("notes") })
    }

    @Test func inheritedCenteredTitleIsRecognizedWithoutExplicitSlideType() throws {
        let title = shape("Owls", type: "ctrTitle").replacingOccurrences(of: "type=\"ctrTitle\" ", with: "")
        let layout = slide(shape("", type: "ctrTitle")).replacingOccurrences(of: "p:sld", with: "p:sldLayout")
        let data = try package([slide(title)], extras: [
            "ppt/slides/_rels/slide1.xml.rels": Data(relations([("layout", "slideLayout", "../slideLayouts/layout.xml", false)]).utf8),
            "ppt/slideLayouts/layout.xml": Data(layout.utf8)
        ])
        #expect(try convert(data).markdown == "# Owls\n")
    }

    @Test func unsupportedMediaAndEquationsKeepDescriptionsAndReportOmissions() throws {
        let media = "<p:pic><p:nvPicPr><p:cNvPr id=\"7\" name=\"Video\" descr=\"An owl calling\"/><p:nvPr><a:videoFile r:link=\"video\"/></p:nvPr></p:nvPicPr></p:pic>"
        let equation = shape("Context").replacingOccurrences(of: "name=\"Shape\"", with: "name=\"Shape\" descr=\"A mathematical formula\"")
            .replacingOccurrences(of: "</a:p>", with: "<a:oMath/></a:p>")
        let data = try package([slide(media + equation)])
        let result = try convert(data)
        #expect(result.markdown.contains("Media: An owl calling"))
        #expect(result.markdown.contains("Context"))
        #expect(result.markdown.contains("Equation: A mathematical formula"))
        #expect(result.notices.contains { $0.contains("2 PowerPoint objects") })
        var options = PowerPointImportOptions()
        options.slideText = false
        #expect(try convert(data, options: options).markdown == "## Slide 1\n")
    }

    @Test func sourceReadsAreBoundedBeforeZIPParsing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PowerPointRead-\(UUID()).pptx")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try package([slide(shape("Text"))])
        try bytes.write(to: url)
        #expect(try PowerPointImportPackage.fileData(at: url) == bytes)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(PowerPointImportPackage.maximumFileSize + 1))
        try handle.close()
        #expect(throws: PowerPointImportError.self) { try PowerPointImportPackage.fileData(at: url) }
    }
}

#if canImport(UIKit)
@MainActor
struct PowerPointImportPlacementTests {
    @Test func mixedBatchPreservesSourcesAndOtherImportsWhenOnePresentationFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PowerPointImport-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Deck.pptx")
        let bad = root.appendingPathComponent("Broken.pptx")
        let word = root.appendingPathComponent("Word.docx")
        let plain = root.appendingPathComponent("Plain.md")
        let bytes = try PowerPointWriter.write(title: "Deck", markdown: "## Topic\n\nBody", theme: .warmPaper)
        try bytes.write(to: source)
        try Data("broken".utf8).write(to: bad)
        try MarkdownToWordConverter.convert(title: "Word", markdown: "# Word\n\nKeep me").write(to: word)
        try Data("# Plain".utf8).write(to: plain)
        let store = DocumentStore(directory: root.appendingPathComponent("Library", isDirectory: true))
        let result = await store.importDocuments(from: [source, bad, word, plain])
        #expect(result.imported.count == 3)
        #expect(result.failedFileNames == ["Broken.pptx"])
        #expect(try Data(contentsOf: source) == bytes)
        let again = await store.importDocuments(from: [source])
        #expect(again.imported.count == 1)
        #expect(again.imported.first?.url != result.imported.first?.url)
    }
}
#endif
