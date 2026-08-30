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

    @Test func tablesBecomeLabeledTextRowsWithoutNativeTableStructure() throws {
        let package = try entries(markdown: """
        # Deck

        ## Habitats

        | Species | Habitat |
        | :--- | ---: |
        | **Barn owl** | [Grassland](https://example.com/grassland) |
        | Little owl | Farmland |
        """)
        let slide = try text("ppt/slides/slide2.xml", in: package)
        let relationships = try text("ppt/slides/_rels/slide2.xml.rels", in: package)

        #expect(slide.contains("<a:t>Species | Habitat</a:t>"))
        #expect(slide.contains("<a:t>Species: Barn owl; Habitat: Grassland</a:t>"))
        #expect(slide.contains("<a:t>Species: Little owl; Habitat: Farmland</a:t>"))
        #expect(!slide.contains("<a:tbl>"))
        #expect(!slide.contains("<a:hlinkClick"))
        #expect(!slide.contains("**Barn owl**"))
        #expect(!relationships.contains("https://example.com/grassland"))
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

    private var tinyPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
    }
}
