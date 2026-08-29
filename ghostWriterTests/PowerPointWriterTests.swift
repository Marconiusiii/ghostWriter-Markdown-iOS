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
        language: String = "en"
    ) throws -> [String: Data] {
        let data = try PowerPointWriter.write(
            title: title,
            markdown: markdown,
            theme: theme,
            sourceDirectory: sourceDirectory,
            documentLanguage: language
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

        #expect(presentation.components(separatedBy: "<p:sldId ").count - 1 == 3)
        #expect(first.contains("Presentation title"))
        #expect(first.contains("Subtitle text."))
        #expect(second.contains("First point"))
        #expect(second.contains("Body."))
        #expect(third.contains("Second point"))
        #expect(third.contains("More body."))
        #expect(second.contains("<p:ph type=\"title\""))
        #expect(second.contains("<p:ph type=\"body\""))
        #expect(contentLayout.contains("<p:ph type=\"title\" idx=\"0\""))
        #expect(contentLayout.contains("<p:ph type=\"body\" idx=\"1\""))
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
        let properties = try text("docProps/app.xml", in: package)

        #expect(slide.contains("Visible paragraph."))
        #expect(!slide.contains("First speaker note."))
        #expect(notes.contains("First speaker note."))
        #expect(notes.contains("Second speaker note."))
        #expect(relationships.contains("relationships/notesSlide"))
        #expect(relationships.contains("../notesSlides/notesSlide2.xml"))
        #expect(properties.contains("<Notes>1</Notes>"))
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
        #expect(slide.contains("lvl=\"1\""))
        #expect(slide.contains("<a:buAutoNum type=\"arabicPeriod\" startAt=\"4\"/>"))
        #expect(slide.contains("<a:buAutoNum type=\"arabicPeriod\" startAt=\"5\"/>"))
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
