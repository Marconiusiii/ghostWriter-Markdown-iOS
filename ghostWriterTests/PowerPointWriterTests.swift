import Foundation
import Testing
import ZIPFoundation
@testable import ghostWriter

struct PowerPointWriterTests {
    private func entries(
        title: String = "Deck",
        markdown: String,
        theme: PowerPointTheme = .warmPaper,
        sourceDirectory: URL? = nil,
        language: String = "en",
        resolvedImages: [String: PowerPointImageLoader.Image]? = nil
    ) throws -> [String: Data] {
        let data = try PowerPointWriter.write(
            title: title,
            markdown: markdown,
            theme: theme,
            sourceDirectory: sourceDirectory,
            documentLanguage: language,
            resolvedImages: resolvedImages
        )
        let archive = try Archive(data: data, accessMode: .read)
        var result: [String: Data] = [:]
        for entry in archive {
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            result[entry.path] = bytes
        }
        return result
    }

    private func text(_ path: String, in entries: [String: Data]) throws -> String {
        String(decoding: try #require(entries[path]), as: UTF8.self)
    }

    @Test func levelTwoHeadingsCreateTitledSlides() throws {
        let package = try entries(markdown: """
        # Presentation title

        Subtitle text.

        ## First point

        Body.

        ## Second point

        More body.
        """)

        let presentation = try text("ppt/presentation.xml", in: package)
        let first = try text("ppt/slides/slide1.xml", in: package)
        let second = try text("ppt/slides/slide2.xml", in: package)
        let third = try text("ppt/slides/slide3.xml", in: package)
        let contentLayout = try text("ppt/slideLayouts/slideLayout2.xml", in: package)
        let master = try text("ppt/slideMasters/slideMaster1.xml", in: package)
        let viewProperties = try text("ppt/viewProps.xml", in: package)

        #expect(presentation.components(separatedBy: "<p:sldId ").count - 1 == 3)
        #expect(first.contains("Presentation title"))
        #expect(first.contains("Subtitle text."))
        #expect(second.contains("First point"))
        #expect(second.contains("Body."))
        #expect(third.contains("Second point"))
        #expect(third.contains("More body."))
        #expect(second.contains("<p:ph type=\"title\""))
        #expect(second.contains("<p:ph type=\"body\""))
        #expect(contentLayout.contains("<p:ph type=\"title\"/>"))
        #expect(contentLayout.contains("<p:ph type=\"body\" idx=\"1\""))
        #expect(contentLayout.contains("<a:spLocks noGrp=\"1\"/>"))
        #expect(contentLayout.contains("<a:endParaRPr lang=\"en-US\"/>"))
        #expect(master.contains("<p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/>"))
        #expect(master.contains("<p:sldLayoutId id=\"2147483650\" r:id=\"rId2\"/>"))
        #expect(master.contains("<p:bg><p:bgRef idx=\"1001\""))
        #expect(master.contains("<p:hf hdr=\"0\" ftr=\"0\" dt=\"0\" sldNum=\"0\"/>"))
        #expect(presentation.contains("<a:lvl9pPr"))
        #expect((try text("ppt/_rels/presentation.xml.rels", in: package)).contains("relationships/theme"))
        #expect(viewProperties.contains("<p:restoredLeft"))
        #expect(viewProperties.contains("<p:cSldViewPr"))
        #expect(viewProperties.contains("<p:notesTextViewPr><p:cViewPr>"))
        #expect(!first.contains("txBox=\"1\""))
        #expect(!second.contains("txBox=\"1\""))
        #expect(!third.contains("txBox=\"1\""))
        #expect(package["ppt/notesMasters/notesMaster1.xml"] == nil)
        #expect(package["ppt/notesMasters/_rels/notesMaster1.xml.rels"] == nil)
        #expect(package["ppt/theme/theme2.xml"] == nil)
        #expect(!presentation.contains("<p:notesMasterIdLst>"))
        #expect(!(try text("ppt/_rels/presentation.xml.rels", in: package)).contains("relationships/notesMaster"))
        #expect(!(try text("[Content_Types].xml", in: package)).contains("notesMaster+xml"))
    }

    @Test func thematicBreakMovesFollowingParagraphsIntoSpeakerNotes() throws {
        let package = try entries(markdown: """
        # Deck

        ## Visible slide

        Visible paragraph.

        ***

        First speaker note.

        Second speaker note.

        ## Next slide

        Next body.
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)
        let notes = try text("ppt/notesSlides/notesSlide2.xml", in: package)
        let relationships = try text("ppt/slides/_rels/slide2.xml.rels", in: package)
        let presentation = try text("ppt/presentation.xml", in: package)
        let presentationRelationships = try text("ppt/_rels/presentation.xml.rels", in: package)
        let notesMasterRelationships = try text("ppt/notesMasters/_rels/notesMaster1.xml.rels", in: package)
        let contentTypes = try text("[Content_Types].xml", in: package)
        let properties = try text("docProps/app.xml", in: package)

        #expect(slide.contains("Visible paragraph."))
        #expect(!slide.contains("First speaker note."))
        #expect(notes.contains("First speaker note."))
        #expect(notes.contains("Second speaker note."))
        #expect(!notes.contains("txBox=\"1\""))
        #expect(relationships.contains("relationships/notesSlide"))
        #expect(relationships.contains("../notesSlides/notesSlide2.xml"))
        #expect(properties.contains("<Notes>1</Notes>"))
        #expect(presentation.contains("<p:notesMasterIdLst>"))
        #expect(presentationRelationships.contains("relationships/notesMaster"))
        #expect(notesMasterRelationships.contains("../theme/theme1.xml"))
        #expect(package["ppt/theme/theme2.xml"] == nil)
        #expect(!contentTypes.contains("/ppt/theme/theme2.xml"))
        #expect(contentTypes.contains("/ppt/notesMasters/notesMaster1.xml"))
        #expect(try #require(presentation.range(of: "<p:sldIdLst>")).lowerBound < #require(presentation.range(of: "<p:notesMasterIdLst>")).lowerBound)
        #expect(notes.contains("<p:ph type=\"sldImg\" idx=\"2\"/>"))
        #expect(notes.contains("<p:ph type=\"body\" idx=\"3\"/>"))
        #expect(notes.contains("<p:ph type=\"sldNum\" idx=\"5\"/>"))
    }

    @Test func listsRemainNativeAndNested() throws {
        let package = try entries(markdown: """
        # Deck

        ## Lists

        - Outer
          - Inner

        4. Fourth
        5. Fifth
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)

        #expect(slide.contains("<a:buChar char=\"•\"/>"))
        #expect(slide.contains("<a:buSzPct val=\"100000\"/>"))
        #expect(slide.contains("<a:buFont typeface=\"Arial\"/>"))
        #expect(slide.contains("lvl=\"1\""))
        #expect(slide.contains("<a:buAutoNum type=\"arabicPeriod\" startAt=\"4\"/>"))
        #expect(slide.contains("<a:buAutoNum type=\"arabicPeriod\"/>"))
        #expect(!slide.contains("startAt=\"5\""))
        #expect(slide.contains("<p:ph type=\"body\" idx=\"1\""))
        #expect(!slide.contains("txBox=\"1\""))
    }

    @Test func orderedListsRestartOnlyAtMarkdownListBoundaries() throws {
        let package = try entries(markdown: """
        # Deck

        ## Numbering

        3. Third
        4. Fourth
           1. Nested first
           2. Nested second

        Between lists.

        8. Eighth
        9. Ninth
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)

        #expect(slide.components(separatedBy: "startAt=\"3\"").count - 1 == 1)
        #expect(slide.components(separatedBy: "startAt=\"1\"").count - 1 == 1)
        #expect(slide.components(separatedBy: "startAt=\"8\"").count - 1 == 1)
        #expect(slide.components(separatedBy: "<a:buAutoNum type=\"arabicPeriod\"/>").count - 1 == 3)
        #expect(!slide.contains("startAt=\"4\""))
        #expect(!slide.contains("startAt=\"2\""))
        #expect(!slide.contains("startAt=\"9\""))
    }

    @Test func tablesRemainNativeWithHeadersAlignmentFormattingAndLinks() throws {
        let package = try entries(markdown: """
        # Deck

        ## Habitats

        | Species | Habitat | Count |
        | :--- | :---: | ---: |
        | **Barn owl** | [Grassland](https://example.com/grassland) | 2 |
        | *Little owl* | Farmland | 4 |
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)
        let relationships = try text("ppt/slides/_rels/slide2.xml.rels", in: package)

        let root = try xmlTree(slide)
        let table = try #require(root.all("a:tbl").first)
        #expect(table.all("a:tblPr").first?.attributes["firstRow"] == "1")
        #expect(table.all("a:gridCol").count == 3)
        let rows = table.all("a:tr")
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.all("a:tc").count == 3 })
        #expect(rows[0].all("a:t").map(\.text) == ["Species", "Habitat", "Count"])
        #expect(rows[1].all("a:t").map(\.text) == ["Barn owl", "Grassland", "2"])
        #expect(rows[2].all("a:t").map(\.text) == ["Little owl", "Farmland", "4"])
        #expect(rows[1].all("a:pPr").map { $0.attributes["algn"] } == ["l", "ctr", "r"])
        #expect(rows[1].all("a:rPr").first?.attributes["b"] == "1")
        #expect(rows[2].all("a:rPr").first?.attributes["i"] == "1")
        let linkID = try #require(table.all("a:hlinkClick").first?.attributes["r:id"])
        #expect(relationships.contains("Id=\"\(linkID)\""))
        #expect(relationships.contains("Target=\"https://example.com/grassland\""))
        #expect(relationships.contains("TargetMode=\"External\""))
        #expect(!slide.contains("**Barn owl**"))
        #expect(!slide.contains("Species: Barn owl"))
    }

    @Test func tablesAndTextKeepSourceOrderAndNonoverlappingFrames() throws {
        let package = try entries(markdown: """
        # Deck

        ## Mixed

        Before the table.

        | Species | Count |
        | --- | --- |
        | Owl | 2 |

        - After the table

        | Place | Count |
        | --- | --- |
        | Woods | 3 |
        """)
        let root = try xmlTree(text("ppt/slides/slide2.xml", in: package))
        let tree = try #require(root.all("p:spTree").first)
        let shapes = tree.children.filter { ["p:sp", "p:graphicFrame"].contains($0.name) }
        #expect(shapes.map(\.name) == ["p:sp", "p:sp", "p:graphicFrame", "p:sp", "p:graphicFrame"])
        let ids = shapes.compactMap { $0.all("p:cNvPr").first?.attributes["id"] }
        #expect(Set(ids).count == shapes.count)
        #expect(root.all("p:ph").filter { $0.attributes["type"] == "body" }.count == 1)
        var previousBottom = 0
        for shape in shapes {
            let off = try #require(shape.all("a:off").first)
            let ext = try #require(shape.all("a:ext").first)
            let y = try #require(Int(off.attributes["y"] ?? ""))
            let height = try #require(Int(ext.attributes["cy"] ?? ""))
            #expect(y >= previousBottom)
            previousBottom = y + height
            #expect(previousBottom <= 6_858_000)
        }
        for shape in shapes where shape.name == "p:graphicFrame" {
            let ext = try #require(shape.all("a:ext").first)
            #expect(shape.all("a:gridCol").reduce(0) { $0 + (Int($1.attributes["w"] ?? "") ?? 0) }
                == Int(ext.attributes["cx"] ?? ""))
            #expect(shape.all("a:tr").reduce(0) { $0 + (Int($1.attributes["h"] ?? "") ?? 0) }
                == Int(ext.attributes["cy"] ?? ""))
        }
    }

    @Test func titleSlideTableLeavesRoomForTitleAndPicture() throws {
        let source = "https://example.com/owl.png"
        let package = try entries(markdown: "# Owls\n\n| Species | Count |\n| --- | --- |\n| Owl | 2 |\n\n![Owl](\(source))",
            resolvedImages: [source: .init(data: tinyPNG, mediaType: "image/png")])
        let root = try xmlTree(text("ppt/slides/slide1.xml", in: package))
        let table = try #require(root.all("p:graphicFrame").first)
        let picture = try #require(root.all("p:pic").first)
        let tableOffset = try #require(table.all("a:off").first)
        let tableSize = try #require(table.all("a:ext").first)
        let pictureOffset = try #require(picture.all("a:off").first)
        #expect(Int(tableOffset.attributes["y"] ?? "") == 1_900_000)
        let tableRight = try #require(Int(tableOffset.attributes["x"] ?? ""))
            + #require(Int(tableSize.attributes["cx"] ?? ""))
        #expect(tableRight < (Int(pictureOffset.attributes["x"] ?? "") ?? 0))
        #expect(root.all("p:cNvPr").contains { $0.attributes["descr"] == "Owl" })
    }

    @Test func tableRowsGrowForWrappedContentAndShortRowsKeepEmptyCells() throws {
        let package = try entries(markdown: """
        # Deck

        ## Wrapping

        | Species | Notes |
        | --- | --- |
        | Owl | A short note. |
        | Another owl | This longer description needs to wrap onto several lines inside its table cell while retaining every word. |
        | Last owl |
        """)
        let root = try xmlTree(text("ppt/slides/slide2.xml", in: package))
        let rows = root.all("a:tr")
        #expect(rows.count == 4)
        #expect((Int(rows[2].attributes["h"] ?? "") ?? 0) > (Int(rows[1].attributes["h"] ?? "") ?? 0))
        #expect(rows[3].all("a:tc").count == 2)
        #expect(rows[3].all("a:tc")[1].all("a:p").count == 1)
        #expect(root.all("a:t").contains { $0.text.hasSuffix("retaining every word.") })
    }

    @Test func tablesUseThemeColorsAndNotesKeepLabeledText() throws {
        for theme in PowerPointTheme.allCases {
            let package = try entries(markdown: """
            # Deck

            ## Table

            | Name | Value |
            | --- | --- |
            | Owl | 2 |

            ***

            | Note | Detail |
            | --- | --- |
            | Source | Counted locally |
            """, theme: theme)
            let root = try xmlTree(text("ppt/slides/slide2.xml", in: package))
            let table = try #require(root.all("a:tbl").first)
            #expect(table.all("a:srgbClr").isEmpty)
            #expect(table.all("a:schemeClr").contains { $0.attributes["val"] == "lt2" })
            #expect(table.all("a:schemeClr").contains { $0.attributes["val"] == "bg1" })
            let notes = try text("ppt/notesSlides/notesSlide2.xml", in: package)
            #expect(notes.contains("Note: Source; Detail: Counted locally"))
            #expect(!notes.contains("<a:tbl>"))
        }
    }

    @Test func listNumberingContinuesAcrossAnEmbeddedTable() throws {
        let package = try entries(markdown: """
        # Deck

        ## List with a table

        3. Third

           | Name | Count |
           | --- | --- |
           | Owl | 2 |

        4. Fourth
        """)
        let root = try xmlTree(text("ppt/slides/slide2.xml", in: package))
        #expect(root.all("a:tbl").count == 1)
        #expect(root.all("a:buAutoNum").map { $0.attributes["startAt"] } == ["3", "4"])
        #expect(root.all("a:t").map(\.text) == ["List with a table", "Third", "Name", "Count", "Owl", "2", "Fourth"])
    }

    @Test func tableCellImagesRemainDescribedSlidePictures() throws {
        let source = "https://example.com/owl.png"
        let package = try entries(markdown: "# Deck\n\n## Image cell\n\n| Species | Image |\n| --- | --- |\n| Owl | ![An owl](\(source)) |",
            resolvedImages: [source: .init(data: tinyPNG, mediaType: "image/png")])
        let root = try xmlTree(text("ppt/slides/slide2.xml", in: package))
        #expect(root.all("a:tbl").count == 1)
        #expect(root.all("p:pic").count == 1)
        #expect(root.all("p:cNvPr").contains { $0.attributes["descr"] == "An owl" })
        #expect(package["ppt/media/image1.png"] == tinyPNG)
    }

    @Test func oversizedTablesFailWithoutFlatteningOrShrinking() throws {
        let rows = Array(repeating: "| Owl | 2 |", count: 20).joined(separator: "\n")
        #expect(throws: PowerPointExportError.slideTooFull("Too tall")) {
            try entries(markdown: "# Deck\n\n## Too tall\n\n| Name | Value |\n| --- | --- |\n\(rows)")
        }
        let header = Array(repeating: "Name", count: 12).joined(separator: " | ")
        let separator = Array(repeating: "---", count: 12).joined(separator: " | ")
        #expect(throws: PowerPointExportError.slideTooFull("Too wide")) {
            try entries(markdown: "# Deck\n\n## Too wide\n\n| \(header) |\n| \(separator) |\n| \(header) |")
        }
    }

    @Test func blockQuotesBecomeLabeledParagraphs() throws {
        let package = try entries(markdown: """
        # Deck

        ## Quote

        > Owls listen carefully.
        >
        > They hunt quietly.
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)

        #expect(slide.components(separatedBy: "<a:t>Quote: </a:t>").count - 1 == 1)
        #expect(slide.contains("<a:t>Owls listen carefully.</a:t>"))
        #expect(slide.contains("<a:t>They hunt quietly.</a:t>"))
    }

    @Test func codeBlocksKeepMonospacedTextAndLineBreaks() throws {
        let package = try entries(markdown: """
        # Deck

        ## Code

        ```swift
        if count < 2 {
            print("owl")
        }
        ```
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)

        #expect(slide.contains("<a:latin typeface=\"Courier New\"/>"))
        #expect(slide.contains("Code (swift):\nif count &lt; 2 {\n    print(\"owl\")\n}"))
        #expect(!slide.contains("```"))
    }

    @Test func taskListsBecomeNativeListItemsWithCompletionLabels() throws {
        let package = try entries(markdown: """
        # Deck

        ## Tasks

        - [x] Find an owl
        - [ ] Record its call
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)

        #expect(slide.contains("<a:t>Completed: </a:t>"))
        #expect(slide.contains("<a:t>Not completed: </a:t>"))
        #expect(slide.contains("<a:t>Find an owl</a:t>"))
        #expect(slide.contains("<a:t>Record its call</a:t>"))
        #expect(slide.components(separatedBy: "<a:buChar ").count - 1 == 2)
        #expect(!slide.contains("[x]"))
        #expect(!slide.contains("[ ]"))
        #expect(!slide.contains("<p:control"))
    }

    @Test func linksUseVisibleTextAndExternalRelationships() throws {
        let package = try entries(markdown: "# Deck\n\n## Links\n\nRead [the guide](https://example.com/guide).")
        let slide = try text("ppt/slides/slide2.xml", in: package)
        let relationships = try text("ppt/slides/_rels/slide2.xml.rels", in: package)

        #expect(slide.contains("the guide"))
        #expect(slide.contains("<a:hlinkClick r:id=\"rId10\"/>"))
        #expect(slide.contains("u=\"sng\""))
        #expect(relationships.contains("Target=\"https://example.com/guide\""))
        #expect(relationships.contains("TargetMode=\"External\""))
    }

    @Test func imagesAreEmbeddedWithDescriptionsAndDecorativeState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-pptx-images-\(UUID().uuidString)")
        let assets = root.appendingPathComponent(".ghostwriter-assets-test")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try tinyPNG.write(to: assets.appendingPathComponent("diagram.png"))

        let package = try entries(
            markdown: "# Deck\n\n## Images\n\n![Process diagram](.ghostwriter-assets-test/diagram.png)\n\n![](.ghostwriter-assets-test/diagram.png)",
            sourceDirectory: root
        )
        let slide = try text("ppt/slides/slide2.xml", in: package)
        let relationships = try text("ppt/slides/_rels/slide2.xml.rels", in: package)

        #expect(package["ppt/media/image1.png"] == tinyPNG)
        #expect(package["ppt/media/image2.png"] == tinyPNG)
        #expect(slide.contains("descr=\"Process diagram\""))
        #expect(slide.contains("<adec:decorative val=\"1\"/>"))
        #expect(relationships.contains("../media/image1.png"))
    }

    @Test func unavailableImagesAreOmittedWithoutFailingTheExport() throws {
        let package = try entries(
            markdown: """
            # Deck

            ## Images

            Text before ![Remote owl](https://example.com/owl.jpg) text after.

            ![Missing owl](.ghostwriter-assets-missing/owl.png)
            """,
            sourceDirectory: FileManager.default.temporaryDirectory
        )
        let slide = try text("ppt/slides/slide2.xml", in: package)
        let relationships = try text("ppt/slides/_rels/slide2.xml.rels", in: package)

        #expect(slide.contains("Text before "))
        #expect(slide.contains(" text after."))
        #expect(slide.contains("cx=\"10728000\""))
        #expect(!slide.contains("<p:pic>"))
        #expect(!relationships.contains("relationships/image"))
        #expect(!package.keys.contains { $0.hasPrefix("ppt/media/") })
    }

    @Test func resolvedRemoteImageEmbedsAlternativeTextWithoutOverlappingTitle() throws {
        let source = "https://example.com/owl.svg"
        let package = try entries(markdown: "# Owls\n\nIntroduction.\n\n![A cute hoot](\(source))",
            resolvedImages: [source: .init(data: tinyPNG, mediaType: "image/png")])
        let slide = try text("ppt/slides/slide1.xml", in: package)
        let relationships = try text("ppt/slides/_rels/slide1.xml.rels", in: package)
        let contentTypes = try text("[Content_Types].xml", in: package)
        #expect(package["ppt/media/image1.png"] == tinyPNG)
        #expect(package["ppt/media/image1.svg"] == nil)
        #expect(slide.contains("descr=\"A cute hoot\""))
        #expect(slide.contains("<a:blip r:embed=\"rId10\"/>"))
        #expect(relationships.contains("Target=\"../media/image1.png\""))
        #expect(!relationships.contains("Target=\"../media/image1.svg\""))
        #expect(contentTypes.contains("image/png"))
        #expect(slide.contains("<a:ln><a:solidFill><a:schemeClr val=\"accent2\"/></a:solidFill></a:ln>"))
        // Title ends at y=1,624,320; body and image start below it at y=1,900,000.
        // Body ends at x=6,491,520; the image column begins at x=6,850,000.
        #expect(slide.contains("<a:off x=\"548640\" y=\"274320\"/><a:ext cx=\"11094720\" cy=\"1350000\"/>"))
        #expect(slide.contains("<a:off x=\"731520\" y=\"1900000\"/><a:ext cx=\"5760000\" cy=\"4300000\"/>"))
        #expect(slide.contains("<a:off x=\"7100000\" y=\"1900000\"/><a:ext cx=\"4300000\" cy=\"4300000\"/>"))
    }

    @Test func selectedThemeAndLanguageAreWrittenIntoThePackage() throws {
        let package = try entries(
            markdown: "# Deck\n\n## Tema\n\nContenido.",
            theme: .highContrastDark,
            language: "es-MX"
        )
        let theme = try text("ppt/theme/theme1.xml", in: package)
        let slide = try text("ppt/slides/slide2.xml", in: package)
        let core = try text("docProps/core.xml", in: package)

        #expect(theme.contains("val=\"000000\""))
        #expect(theme.contains("val=\"FFFFFF\""))
        #expect(theme.contains("val=\"FFD60A\""))
        #expect(slide.contains("lang=\"es-MX\""))
        #expect(core.contains("<dc:language>es-MX</dc:language>"))
    }

    @Test func everyXMLPartIsWellFormed() throws {
        let package = try entries(markdown: "# Deck\n\n## Slide\n\nBody.\n\n***\n\nNotes.")
        for (path, contents) in package where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
            let parser = XMLParser(data: contents)
            #expect(parser.parse(), "Malformed XML at \(path): \(parser.parserError?.localizedDescription ?? "unknown error")")
        }
    }

    @Test func denseSlidesFailInsteadOfShrinkingOrTruncating() throws {
        let paragraph = String(repeating: "Long accessible presentation text ", count: 80)
        #expect(throws: PowerPointExportError.slideTooFull("Dense slide")) {
            try PowerPointWriter.write(
                title: "Deck",
                markdown: "# Deck\n\n## Dense slide\n\n\(paragraph)"
            )
        }
    }

    private func xmlTree(_ text: String) throws -> TestXMLNode {
        let capture = TestXMLCapture()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = capture
        #expect(parser.parse(), "Malformed XML: \(parser.parserError?.localizedDescription ?? "unknown error")")
        return try #require(capture.root)
    }

    private var tinyPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
    }
}

nonisolated private final class TestXMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [TestXMLNode] = []
    init(_ name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }
    func all(_ name: String) -> [TestXMLNode] {
        (self.name == name ? [self] : []) + children.flatMap { $0.all(name) }
    }
}

nonisolated private final class TestXMLCapture: NSObject, XMLParserDelegate {
    var root: TestXMLNode?
    private var stack: [TestXMLNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = TestXMLNode(elementName, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        stack.removeLast()
    }
}
