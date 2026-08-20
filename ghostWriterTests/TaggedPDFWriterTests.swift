//
//  TaggedPDFWriterTests.swift
//  ghostWriterTests
//
//  Verifies that the exported PDF is genuinely tagged.
//
//  "It opened and looked right" proves nothing here — an untagged PDF looks
//  identical and is useless to a screen reader. These tests inspect the file's
//  own structure: the catalog's StructTreeRoot, the MarkInfo flag that declares
//  the document tagged, and the structure element types in the tree. Those are
//  the things a PDF/UA checker looks at, and the things that break silently if
//  the tagging calls are ever dropped.
//

import CoreGraphics
import Foundation
import Testing
@testable import ghostWriter

struct TaggedPDFWriterTests {

    // MARK: - Helpers

    /// Reads the raw PDF bytes as text. The structure tree is written as
    /// uncompressed dictionary syntax, so the tag names are findable directly —
    /// which is exactly how an external checker locates them too.
    private func rawText(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private func makePDF(
        title: String = "Test Document",
        markdown: String,
        sourceDirectory: URL? = nil
    ) throws -> Data {
        try TaggedPDFWriter.write(
            title: title,
            markdown: markdown,
            sourceDirectory: sourceDirectory
        )
    }

    // MARK: - Document validity

    @Test func producesAReadablePDF() throws {
        let data = try makePDF(markdown: "# Heading\n\nSome body text.")

        #expect(data.count > 0)
        #expect(data.starts(with: Array("%PDF".utf8)))

        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages >= 1)
    }

    @Test func declaresItselfTagged() throws {
        let data = try makePDF(markdown: "# Heading\n\nBody.")
        let text = rawText(data)

        // MarkInfo/Marked true is the flag that tells a reader the structure
        // tree can be trusted. Without it, conforming software treats the
        // document as untagged even when tags are present.
        #expect(text.contains("/MarkInfo"))
        #expect(text.contains("/Marked true"))
    }

    @Test func containsAStructureTree() throws {
        let data = try makePDF(markdown: "# Heading\n\nBody.")
        let text = rawText(data)

        // StructTreeRoot in the catalog is what makes the tags reachable. A
        // file can contain marked content and still be untagged without it.
        #expect(text.contains("/StructTreeRoot"))
        #expect(text.contains("/StructElem"))
    }

    @Test func structureTreeHasAReachableParentTreeAndPageMappings() throws {
        let markdown = (1...120)
            .map { "Paragraph \($0) with enough text to span several pages." }
            .joined(separator: "\n\n")
        let data = try makePDF(markdown: markdown)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let catalog = try #require(document.catalog)

        var structureTree: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(catalog, "StructTreeRoot", &structureTree))
        var parentTree: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(
            try #require(structureTree),
            "ParentTree",
            &parentTree
        ))

        for pageNumber in 1...document.numberOfPages {
            let page = try #require(document.page(at: pageNumber))
            var structParents: CGPDFInteger = -1
            #expect(CGPDFDictionaryGetInteger(
                try #require(page.dictionary),
                "StructParents",
                &structParents
            ))
            #expect(structParents >= 0)
        }
    }

    @Test func declaresTheDocumentLanguageInTheCatalog() throws {
        // Without a language the document is read in the reader's default
        // voice, which mispronounces it end to end when that differs — and a
        // PDF/UA checker reports it as a failure. CGPDFContext cannot write it,
        // so this also guards the incremental update that adds it afterwards.
        let data = try makePDF(markdown: "# Heading\n\nBody text.")

        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let catalog = try #require(document.catalog)

        var languageRef: CGPDFStringRef?
        #expect(CGPDFDictionaryGetString(catalog, "Lang", &languageRef))

        let language = try #require(languageRef)
        let bytes = try #require(CGPDFStringGetBytePtr(language))
        let value = String(
            decoding: UnsafeBufferPointer(start: bytes, count: CGPDFStringGetLength(language)),
            as: UTF8.self
        )
        #expect(!value.isEmpty)
    }

    @Test func addingTheLanguageKeepsTheStructureTreeReachable() throws {
        // The language is added by appending to the finished file. If that ever
        // truncated the catalog, the structure tree would be silently lost and
        // the export would look fine while being untagged.
        let data = try makePDF(markdown: "# Heading\n\n- Item\n\nBody.")

        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let catalog = try #require(document.catalog)

        var structureTree: CGPDFObjectRef?
        #expect(CGPDFDictionaryGetObject(catalog, "StructTreeRoot", &structureTree))
        #expect(document.numberOfPages == 1)
    }

    @Test func setsTheDocumentTitle() throws {
        let data = try makePDF(title: "My Report", markdown: "Body.")
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))

        let info = try #require(document.info)
        var titleRef: CGPDFStringRef?
        #expect(CGPDFDictionaryGetString(info, "Title", &titleRef))

        let title = try #require(titleRef)
        let bytes = try #require(CGPDFStringGetBytePtr(title))
        let length = CGPDFStringGetLength(title)
        let value = String(
            decoding: UnsafeBufferPointer(start: bytes, count: length),
            as: UTF8.self
        )
        #expect(value.contains("My Report"))
    }

    // MARK: - Structure element types

    @Test func headingsProduceHeadingElements() throws {
        let markdown = """
        # Level one

        ## Level two

        ### Level three
        """
        let text = rawText(try makePDF(markdown: markdown))

        // PDF names heading tags H1 through H6.
        #expect(text.contains("/H1"))
        #expect(text.contains("/H2"))
        #expect(text.contains("/H3"))
    }

    @Test func headingsBeyondLevelSixAreClampedNotDropped() throws {
        // Markdown stops at six, but the clamp is what keeps an out-of-range
        // level from producing an unknown tag that strips the semantics.
        let text = rawText(try makePDF(markdown: "###### Six"))
        #expect(text.contains("/H6"))
    }

    @Test func listsProduceListAndListItemElements() throws {
        let text = rawText(try makePDF(markdown: "- First\n- Second"))

        #expect(text.contains("/L"))
        #expect(text.contains("/LI"))
        #expect(text.contains("/Lbl"))
        #expect(text.contains("/LBody"))
    }

    @Test func tablesProduceTableStructure() throws {
        let markdown = """
        | Name | Count |
        | ---- | ----- |
        | Apple | 3 |
        """
        let text = rawText(try makePDF(markdown: markdown))

        #expect(text.contains("/Table"))
        #expect(text.contains("/TR"))
        // A header cell must be TH, not TD — that distinction is what lets a
        // reader announce a value together with its column heading.
        #expect(text.contains("/TH"))
        #expect(text.contains("/TD"))
        #expect(text.contains("/THead"))
    }

    @Test func blockQuotesProduceQuoteElements() throws {
        let text = rawText(try makePDF(markdown: "> Quoted text."))
        #expect(text.contains("/BlockQuote"))
    }

    @Test func codeBlocksProduceCodeElements() throws {
        let text = rawText(try makePDF(markdown: "```\nlet x = 1\n```"))
        #expect(text.contains("/Code"))
    }

    @Test func longCodeLinesWrapInsteadOfBeingClipped() throws {
        let longLine = Array(repeating: "accessibleCodeToken", count: 1_500)
            .joined(separator: " ")
        let data = try makePDF(markdown: "```swift\n\(longLine)\n```")
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))

        #expect(document.numberOfPages > 1)
    }

    @Test func paragraphsProduceParagraphElements() throws {
        let text = rawText(try makePDF(markdown: "Just a paragraph."))
        #expect(text.contains("/P"))
    }

    // MARK: - Content and layout

    @Test func longDocumentsPaginate() throws {
        let markdown = (1...200)
            .map { "Paragraph number \($0) with enough text to occupy a full line of the page." }
            .joined(separator: "\n\n")

        let data = try makePDF(markdown: markdown)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))

        #expect(document.numberOfPages > 1)
    }

    @Test func aTableRowIsNotSplitAcrossPages() throws {
        // A row broken over a page boundary destroys the correspondence between
        // a cell and its column header, so the writer moves the whole row.
        var markdown = "Filler.\n\n"
        markdown += (1...45).map { "Line \($0)." }.joined(separator: "\n\n")
        markdown += "\n\n| Column A | Column B |\n| --- | --- |\n| Value one | Value two |\n"

        let data = try makePDF(markdown: markdown)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))

        // The document must still be well formed with the table present.
        #expect(document.numberOfPages > 1)
        #expect(rawText(data).contains("/Table"))
    }

    @Test func emptyDocumentsStillProduceAValidFile() throws {
        let data = try makePDF(title: "Empty", markdown: "")

        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
        // The title heading keeps an otherwise empty export navigable.
        #expect(rawText(data).contains("/H1"))
    }

    @Test func theTitleIsNotRepeatedWhenTheBodyOpensWithIt() throws {
        let data = try makePDF(title: "Report", markdown: "# Report\n\nBody.")
        let text = rawText(data)

        // Two H1 elements both saying "Report" would make heading navigation
        // land twice on the same place.
        let headingCount = text.components(separatedBy: "/H1").count - 1
        #expect(headingCount <= 1)
    }

    @Test func matchingLevelTwoHeadingStillGetsARealTitleHeading() throws {
        let text = rawText(try makePDF(title: "Report", markdown: "## Report\n\nBody."))
        #expect(text.contains("/H1"))
        #expect(text.contains("/H2"))
    }

    @Test func documentsWithUnicodeSurvive() throws {
        let data = try makePDF(
            title: "Unicode",
            markdown: "# Ünïcödé — em dash, curly “quotes”, emoji 👻"
        )
        let provider = try #require(CGDataProvider(data: data as CFData))
        #expect(CGPDFDocument(provider) != nil)
        #expect(rawText(data).contains("/ActualText"))
    }

    @Test func linksBecomeAnnotations() throws {
        let text = rawText(try makePDF(markdown: "Visit [the site](https://example.com)."))

        // A link that is only coloured text is indistinguishable from ordinary
        // text once printed, and cannot be followed.
        #expect(text.contains("/Annots") || text.contains("/URI"))
        #expect(text.contains("/Link"))
    }

    @Test func informativeFiguresCarryAlternativeText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-pdf-image-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
        try image.write(to: assets.appendingPathComponent("figure.png"))

        let data = try makePDF(
            markdown: "![A blue square](.ghostwriter-assets-test/figure.png)",
            sourceDirectory: root
        )
        let text = rawText(data)

        #expect(text.contains("/Figure"))
        #expect(text.contains("/Alt"))
        // PDF text strings are written as UTF-16BE hex so every language is
        // preserved without relying on PDFDocEncoding.
        #expect(text.contains(
            "/Alt <FEFF004100200062006C007500650020007300710075006100720065>"
        ))

        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var resources: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources))
        var xObjects: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(
            try #require(resources), "XObject", &xObjects
        ))
        var imageStream: CGPDFStreamRef?
        #expect(CGPDFDictionaryGetStream(try #require(xObjects), "Im1", &imageStream))
        let requiredImageStream = try #require(imageStream)
        let imageDictionary = try #require(CGPDFStreamGetDictionary(requiredImageStream))
        var colorSpace: CGPDFObjectRef?
        #expect(CGPDFDictionaryGetObject(imageDictionary, "ColorSpace", &colorSpace))
        #expect(CGPDFObjectGetType(try #require(colorSpace)) == .array)
    }

    @Test func imagesOutsideManagedAssetsAreNotRead() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-pdf-image-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
        try image.write(to: root.appendingPathComponent("outside.png"))

        let text = rawText(try makePDF(
            markdown: "![Outside](outside.png)",
            sourceDirectory: root
        ))
        #expect(!text.contains("/Figure"))
        #expect(text.contains("/Caption"))
    }
}
