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
        #expect(markdown.contains("[^1]: Footnote text"))
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
}
