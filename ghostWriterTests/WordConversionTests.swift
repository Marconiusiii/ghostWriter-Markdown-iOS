import Foundation
import Testing
@testable import ghostWriter

struct WordConversionTests {
    @Test func markdownBuildsSemanticWordModel() throws {
        let markdown = """
        # Guide

        A **bold** and *italic* [link](https://example.com).

        3. First
        4. Second

        | Name | Role |
        | --- | --- |
        | Morgan | Writer |
        """

        let document = MarkdownToWordConverter.document(from: markdown)
        guard case .paragraph(let heading) = document.blocks[0] else {
            Issue.record("Expected a heading paragraph")
            return
        }
        #expect(heading.headingLevel == 1)
        #expect(heading.runs.map(\.text).joined() == "Guide")

        guard case .paragraph(let paragraph) = document.blocks[1] else {
            Issue.record("Expected a body paragraph")
            return
        }
        #expect(paragraph.runs.contains { $0.bold && $0.text == "bold" })
        #expect(paragraph.runs.contains { $0.italic && $0.text == "italic" })
        #expect(paragraph.runs.contains {
            $0.hyperlink == "https://example.com" && $0.text == "link"
        })

        guard case .paragraph(let listItem) = document.blocks[2] else {
            Issue.record("Expected a list paragraph")
            return
        }
        #expect(listItem.list?.kind == .numbered(start: 3))
        guard case .table(let table) = document.blocks.last else {
            Issue.record("Expected a table")
            return
        }
        #expect(table.rows.count == 2)
        #expect(table.rows[0].isHeader)
    }

    @Test func generatedWordDocumentContainsRequiredPartsAndRoundTrips() throws {
        let markdown = """
        ## Accessible export

        This has **strong text**, ~~removed text~~, and [a link](https://example.com?a=1&b=2).

        - One
            - Nested

        > A quotation

        ```
        let value = 1
        ```
        """
        let data = try MarkdownToWordConverter.convert(
            title: "Export & Review",
            markdown: markdown
        )
        let entries = try WordPackage.entries(
            from: data,
            paths: [
                "[Content_Types].xml",
                "word/document.xml",
                "word/styles.xml",
                "word/numbering.xml",
                "word/_rels/document.xml.rels",
                "docProps/core.xml"
            ]
        )
        #expect(entries.count == 6)
        let documentData = try #require(entries["word/document.xml"])
        let documentXML = try #require(String(data: documentData, encoding: .utf8))
        #expect(documentXML.contains("w:val=\"Heading2\""))
        #expect(documentXML.contains("<w:b/>"))
        #expect(documentXML.contains("<w:strike/>"))
        #expect(documentXML.contains("<w:numPr>"))
        #expect(documentXML.contains("w:val=\"Quote\""))
        #expect(documentXML.contains("w:val=\"CodeBlock\""))

        let roundTrip = try WordToMarkdownConverter.convert(data: data)
        #expect(roundTrip.contains("## Accessible export"))
        #expect(roundTrip.contains("**strong text**"))
        #expect(roundTrip.contains("~~removed text~~"))
        #expect(roundTrip.contains("[a link](https://example.com?a=1&b=2)"))
        #expect(roundTrip.contains("- One"))
        #expect(roundTrip.contains("> A quotation"))
        #expect(roundTrip.contains("```\nlet value = 1\n```"))
    }

    @Test func inlineParserPreservesEscapesAndCombinedEmphasis() {
        let runs = MarkdownToWordConverter.inlineRuns(
            #"A \*literal\* and ***important*** value"#
        )
        #expect(runs.map(\.text).joined() == "A *literal* and important value")
        #expect(runs.contains {
            $0.text == "important" && $0.bold && $0.italic
        })
        #expect(!runs.contains {
            $0.text == "literal" && ($0.bold || $0.italic)
        })
    }

    @Test func importedParagraphTextCannotAccidentallyBecomeAList() {
        let document = WordDocumentModel(blocks: [
            .paragraph(WordParagraph(runs: [WordRun(text: "- ordinary text")])),
            .paragraph(WordParagraph(runs: [WordRun(text: "7. ordinary text")]))
        ])
        let markdown = WordToMarkdownConverter.markdown(from: document)
        #expect(markdown.contains("\\- ordinary text"))
        #expect(markdown.contains("7\\. ordinary text"))
    }

    @Test func importsIndependentWordprocessingMLFixture() throws {
        let data = try fixtureDocument()
        let markdown = try WordToMarkdownConverter.convert(data: data)

        #expect(markdown.contains("## Imported heading"))
        #expect(markdown.contains("**Bold**"))
        #expect(markdown.contains("*italic*"))
        #expect(markdown.contains("[website](https://example.com)"))
        #expect(markdown.contains("3. First"))
        #expect(markdown.contains("4. Second"))
        #expect(markdown.contains("| Column |"))
        #expect(markdown.contains("| Value |"))
        #expect(markdown.contains("Inserted"))
        #expect(!markdown.contains("Deleted"))
        #expect(markdown.contains("\\[Image: Diagram\\]"))
        #expect(markdown.contains("[^1]"))
        #expect(!markdown.contains("\\[^1\\]"))
        #expect(markdown.contains("[^1]: Footnote text"))
    }

    @Test func importsListsFromParagraphStylesAndNumberingStyles() throws {
        let data = try styleBasedListFixture()
        let markdown = try WordToMarkdownConverter.convert(data: data)

        #expect(markdown.contains("- First bullet\n    - Nested bullet"))
        #expect(markdown.contains("3. Third\n4. Fourth\n    1. Nested number"))
        #expect(markdown.contains("5. Direct numbering override"))
        #expect(markdown.contains("7. Restarted numbering"))
        #expect(markdown.contains("Plain paragraph"))
        #expect(!markdown.contains("- Plain paragraph"))
        #expect(!markdown.contains("1. Plain paragraph"))
        #expect(markdown.contains("- Numbering style link"))
    }

    @Test func rendersContinuousFormattingSpansWithoutMarkerPiles() {
        let document = WordDocumentModel(blocks: [
            .paragraph(WordParagraph(runs: [
                WordRun(text: "Both", bold: true, italic: true),
                WordRun(text: ", "),
                WordRun(text: "italic ", italic: true),
                WordRun(text: "with bold", bold: true, italic: true),
                WordRun(text: " text", italic: true),
                WordRun(text: ", "),
                WordRun(text: "bold ", bold: true),
                WordRun(text: "with italic", bold: true, italic: true),
                WordRun(text: " text", bold: true),
                WordRun(text: ", "),
                WordRun(text: "underlined", underline: true)
            ]))
        ])

        let markdown = WordToMarkdownConverter.markdown(from: document)
        #expect(markdown == "***Both***, *italic **with bold** text*, **bold *with italic* text**, <u>underlined</u>")
    }

    @Test func trimsFormattingMarkersAwayFromBoundaryWhitespace() {
        let document = WordDocumentModel(blocks: [
            .paragraph(WordParagraph(runs: [
                WordRun(text: " leading and trailing ", italic: true)
            ]))
        ])

        #expect(
            WordToMarkdownConverter.markdown(from: document)
                == "*leading and trailing*"
        )
    }

    @Test func groupsFormattedRunsInsideOneLink() {
        let destination = "https://example.com"
        let document = WordDocumentModel(blocks: [
            .paragraph(WordParagraph(runs: [
                WordRun(text: "Read ", italic: true, hyperlink: destination),
                WordRun(text: "this", bold: true, italic: true, hyperlink: destination)
            ]))
        ])

        #expect(
            WordToMarkdownConverter.markdown(from: document)
                == "[*Read **this***](https://example.com)"
        )
    }

    @Test func importsDirectInheritedAndExplicitlyDisabledTextDecoration() throws {
        let markdown = try WordToMarkdownConverter.convert(
            data: try decoratedTextFixture()
        )

        #expect(markdown.contains("*Direct italic*"))
        #expect(markdown.contains("*Inherited italic*"))
        #expect(markdown.contains("<u>Direct underline</u>"))
        #expect(markdown.contains("<u>Inherited underline</u>"))
        #expect(markdown.contains("***Complex script bold italic***"))
        #expect(markdown.contains("Plain override"))
        #expect(!markdown.contains("*Plain override*"))
        #expect(!markdown.contains("<u>Plain override</u>"))
    }

    @Test func underlineRoundTripsThroughWordprocessingML() throws {
        let markdown = "A <u>clear **bold** underline</u>."
        let data = try MarkdownToWordConverter.convert(title: "Underline", markdown: markdown)
        let entries = try WordPackage.entries(from: data, paths: ["word/document.xml"])
        let documentData = try #require(entries["word/document.xml"])
        let xml = try #require(String(data: documentData, encoding: .utf8))

        #expect(xml.contains("<w:u w:val=\"single\"/>"))
        #expect(try WordToMarkdownConverter.convert(data: data) == markdown)
    }

    @Test func importsEmbeddedInformativeAndDecorativeImages() throws {
        let data = try imageFixture(includeMissingAlternativeText: false)
        let imported = try WordToMarkdownConverter.importDocument(
            data: data,
            sourceDirectory: nil,
            assetDirectoryName: ".ghostwriter-assets-test"
        )

        #expect(imported.assets.count == 2)
        #expect(imported.assets.allSatisfy { $0.data == tinyPNG })
        #expect(imported.markdown.contains(
            "![A blue square](.ghostwriter-assets-test/image1.png)"
        ))
        #expect(imported.markdown.contains(
            "![](.ghostwriter-assets-test/image2.png)"
        ))
        #expect(imported.imagesNeedingAlternativeText == 0)
    }

    @Test func reportsWordImageWithNoAccessibilityDesignation() throws {
        let imported = try WordToMarkdownConverter.importDocument(
            data: try imageFixture(includeMissingAlternativeText: true),
            sourceDirectory: nil,
            assetDirectoryName: ".ghostwriter-assets-test"
        )

        #expect(imported.imagesNeedingAlternativeText == 1)
        #expect(imported.markdown.contains(
            "![](.ghostwriter-assets-test/image3.png)"
        ))
    }

    @Test func exportsLocalImagesWithAlternativeAndDecorativeMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ghostWriterImageExport-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try tinyPNG.write(to: directory.appendingPathComponent("informative.png"))
        try tinyPNG.write(to: directory.appendingPathComponent("decorative.png"))

        let data = try MarkdownToWordConverter.convert(
            title: "Images",
            markdown: "![A blue square](informative.png)\n\n![](decorative.png)",
            sourceDirectory: directory
        )
        let entries = try WordPackage.entries(from: data, paths: [
            "word/document.xml",
            "word/_rels/document.xml.rels",
            "word/media/image1.png",
            "word/media/image2.png"
        ])
        #expect(entries["word/media/image1.png"] == tinyPNG)
        #expect(entries["word/media/image2.png"] == tinyPNG)
        let documentXML = try #require(
            entries["word/document.xml"].flatMap { String(data: $0, encoding: .utf8) }
        )
        #expect(documentXML.contains("descr=\"A blue square\""))
        #expect(documentXML.contains("<adec:decorative val=\"1\"/>"))
        let relationships = try #require(
            entries["word/_rels/document.xml.rels"].flatMap {
                String(data: $0, encoding: .utf8)
            }
        )
        #expect(relationships.components(separatedBy: "/relationships/image").count == 3)

        let roundTrip = try WordToMarkdownConverter.importDocument(
            data: data,
            sourceDirectory: nil,
            assetDirectoryName: ".ghostwriter-assets-roundtrip"
        )
        #expect(roundTrip.markdown.contains("![A blue square]("))
        #expect(roundTrip.markdown.contains("![]("))
        #expect(roundTrip.imagesNeedingAlternativeText == 0)
    }

    @Test func rejectsEncryptedPackage() throws {
        let data = try WordPackage.create(entries: [
            "EncryptionInfo": Data("encrypted".utf8),
            "EncryptedPackage": Data("contents".utf8)
        ])
        #expect(throws: WordConversionError.unsupportedEncryptedDocument) {
            try WordToMarkdownConverter.convert(data: data)
        }
    }

    private func fixtureDocument() throws -> Data {
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>
        <w:p><w:pPr><w:pStyle w:val="CustomHeading"/></w:pPr><w:r><w:t>Imported heading</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold</w:t></w:r><w:r><w:t> and </w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>italic</w:t></w:r><w:r><w:t> with </w:t></w:r><w:hyperlink r:id="rId9"><w:r><w:t>website</w:t></w:r></w:hyperlink><w:r><w:t>.</w:t></w:r></w:p>
        <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr><w:r><w:t>First</w:t></w:r></w:p>
        <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr><w:r><w:t>Second</w:t></w:r></w:p>
        <w:tbl><w:tr><w:trPr><w:tblHeader/></w:trPr><w:tc><w:p><w:r><w:t>Column</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Value</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:ins><w:r><w:t>Inserted</w:t></w:r></w:ins><w:del><w:r><w:t>Deleted</w:t></w:r></w:del><w:r><w:drawing><wp:docPr id="1" name="Picture" descr="Diagram"/></w:drawing></w:r><w:r><w:footnoteReference w:id="1"/></w:r></w:p>
        </w:body></w:document>
        """
        let styles = """
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:styleId="BaseHeading"><w:name w:val="heading 2"/><w:pPr><w:outlineLvl w:val="1"/></w:pPr></w:style><w:style w:type="paragraph" w:styleId="CustomHeading"><w:name w:val="Section title"/><w:basedOn w:val="BaseHeading"/></w:style></w:styles>
        """
        let numbering = """
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="2"><w:lvl w:ilvl="0"><w:start w:val="3"/><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum><w:num w:numId="7"><w:abstractNumId w:val="2"/></w:num></w:numbering>
        """
        let relationships = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com" TargetMode="External"/></Relationships>
        """
        let footnotes = """
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnote w:id="1"><w:p><w:r><w:t>Footnote text</w:t></w:r></w:p></w:footnote></w:footnotes>
        """
        return try WordPackage.create(entries: [
            "word/document.xml": Data(document.utf8),
            "word/styles.xml": Data(styles.utf8),
            "word/numbering.xml": Data(numbering.utf8),
            "word/_rels/document.xml.rels": Data(relationships.utf8),
            "word/footnotes.xml": Data(footnotes.utf8)
        ])
    }

    private var tinyPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
    }

    private func imageFixture(includeMissingAlternativeText: Bool) throws -> Data {
        let missing = includeMissingAlternativeText
            ? "<w:p><w:r><w:drawing><wp:inline><wp:docPr id=\"3\" name=\"Picture 3\"/><a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed=\"rIdImage3\"/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
            : ""
        let document = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" xmlns:adec="http://schemas.microsoft.com/office/drawing/2017/decorative"><w:body>
        <w:p><w:r><w:drawing><wp:inline><wp:docPr id="1" name="Picture 1" descr="A blue square"/><a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rIdImage1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        <w:p><w:r><w:drawing><wp:inline><wp:docPr id="2" name="Picture 2"><a:extLst><a:ext><adec:decorative val="1"/></a:ext></a:extLst></wp:docPr><a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rIdImage2"/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        \(missing)
        </w:body></w:document>
        """
        let relationships = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdImage1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/><Relationship Id="rIdImage2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image2.png"/><Relationship Id="rIdImage3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image3.png"/></Relationships>
        """
        return try WordPackage.create(entries: [
            "word/document.xml": Data(document.utf8),
            "word/_rels/document.xml.rels": Data(relationships.utf8),
            "word/media/image1.png": tinyPNG,
            "word/media/image2.png": tinyPNG,
            "word/media/image3.png": tinyPNG
        ])
    }

    private func styleBasedListFixture() throws -> Data {
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:pPr><w:pStyle w:val="BulletBase"/></w:pPr><w:r><w:t>First bullet</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="BulletNested"/></w:pPr><w:r><w:t>Nested bullet</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="NumberBase"/></w:pPr><w:r><w:t>Third</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="NumberBase"/></w:pPr><w:r><w:t>Fourth</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="NumberNested"/></w:pPr><w:r><w:t>Nested number</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="BulletBase"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="20"/></w:numPr></w:pPr><w:r><w:t>Direct numbering override</w:t></w:r></w:p>
        <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="21"/></w:numPr></w:pPr><w:r><w:t>Restarted numbering</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="NoList"/></w:pPr><w:r><w:t>Plain paragraph</w:t></w:r></w:p>
        <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="32"/></w:numPr></w:pPr><w:r><w:t>Numbering style link</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let styles = """
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:style w:type="paragraph" w:styleId="BulletBase"><w:name w:val="Bullet base"/><w:pPr><w:numPr><w:numId w:val="10"/></w:numPr></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="BulletNested"><w:name w:val="Nested bullet"/><w:basedOn w:val="BulletBase"/></w:style>
        <w:style w:type="paragraph" w:styleId="NumberBase"><w:name w:val="Number base"/><w:pPr><w:numPr><w:numId w:val="20"/></w:numPr></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="NumberNested"><w:name w:val="Nested number"/><w:basedOn w:val="NumberBase"/></w:style>
        <w:style w:type="paragraph" w:styleId="NoList"><w:name w:val="No list"/><w:basedOn w:val="NumberBase"/><w:pPr><w:numPr><w:numId w:val="0"/></w:numPr></w:pPr></w:style>
        <w:style w:type="numbering" w:styleId="LinkedNumberingStyle"><w:name w:val="Linked numbering"/><w:pPr><w:numPr><w:numId w:val="30"/></w:numPr></w:pPr></w:style>
        </w:styles>
        """
        let numbering = """
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:abstractNum w:abstractNumId="10"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:pStyle w:val="BulletBase"/></w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:pStyle w:val="BulletNested"/></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="20"><w:lvl w:ilvl="0"><w:start w:val="3"/><w:numFmt w:val="decimal"/><w:pStyle w:val="NumberBase"/></w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="NumberNested"/></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="31"><w:styleLink w:val="LinkedNumberingStyle"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="32"><w:numStyleLink w:val="LinkedNumberingStyle"/></w:abstractNum>
        <w:num w:numId="10"><w:abstractNumId w:val="10"/></w:num>
        <w:num w:numId="20"><w:abstractNumId w:val="20"/></w:num>
        <w:num w:numId="21"><w:abstractNumId w:val="20"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="7"/></w:lvlOverride></w:num>
        <w:num w:numId="30"><w:abstractNumId w:val="31"/></w:num>
        <w:num w:numId="32"><w:abstractNumId w:val="32"/></w:num>
        </w:numbering>
        """
        return try WordPackage.create(entries: [
            "word/document.xml": Data(document.utf8),
            "word/styles.xml": Data(styles.utf8),
            "word/numbering.xml": Data(numbering.utf8)
        ])
    }

    private func decoratedTextFixture() throws -> Data {
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:rPr><w:i/></w:rPr><w:t>Direct italic</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:rStyle w:val="InheritedItalic"/></w:rPr><w:t>Inherited italic</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>Direct underline</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:rStyle w:val="InheritedUnderline"/></w:rPr><w:t>Inherited underline</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:bCs/><w:iCs/></w:rPr><w:t>Complex script bold italic</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:rStyle w:val="PlainOverride"/></w:rPr><w:t>Plain override</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let styles = """
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:style w:type="character" w:styleId="DecorationBase"><w:name w:val="Decoration base"/><w:rPr><w:i/><w:u w:val="single"/></w:rPr></w:style>
        <w:style w:type="character" w:styleId="InheritedItalic"><w:name w:val="Inherited italic"/><w:basedOn w:val="DecorationBase"/><w:rPr><w:u w:val="none"/></w:rPr></w:style>
        <w:style w:type="character" w:styleId="InheritedUnderline"><w:name w:val="Inherited underline"/><w:basedOn w:val="DecorationBase"/><w:rPr><w:i w:val="0"/></w:rPr></w:style>
        <w:style w:type="character" w:styleId="PlainOverride"><w:name w:val="Plain override"/><w:basedOn w:val="DecorationBase"/><w:rPr><w:i w:val="0"/><w:u w:val="none"/></w:rPr></w:style>
        </w:styles>
        """
        return try WordPackage.create(entries: [
            "word/document.xml": Data(document.utf8),
            "word/styles.xml": Data(styles.utf8)
        ])
    }
}
