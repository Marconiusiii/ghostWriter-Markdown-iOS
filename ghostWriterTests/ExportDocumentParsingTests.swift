//
//  ExportDocumentParsingTests.swift
//  ghostWriterTests
//
//  Covers the shared block and inline model the PDF, EPUB, and plain text
//  exports are built on. A defect here shows up in all three at once.
//

import Testing
@testable import ghostWriter

struct ExportDocumentParsingTests {

    @Test func headingsCarryTheirLevel() {
        let document = MarkdownDocumentParser.parse("# One\n\n### Three")

        #expect(document.blocks.count == 2)
        guard case .heading(let first, let firstContent) = document.blocks[0],
              case .heading(let second, _) = document.blocks[1] else {
            Issue.record("Expected two headings")
            return
        }
        #expect(first == 1)
        #expect(second == 3)
        #expect(firstContent.plainText == "One")
    }

    @Test func setextHeadingsAreRecognised() {
        let document = MarkdownDocumentParser.parse("Title\n=====\n\nSub\n---")

        guard case .heading(let first, _) = document.blocks[0],
              case .heading(let second, _) = document.blocks[1] else {
            Issue.record("Expected setext headings")
            return
        }
        #expect(first == 1)
        #expect(second == 2)
    }

    @Test func emphasisNests() {
        let document = MarkdownDocumentParser.parse("A **bold *and italic* run**.")

        guard case .paragraph(let content) = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }

        // The nesting itself is the point: a flattened model would lose the
        // italic inside the bold.
        let strong = content.compactMap { span -> [ExportInline]? in
            if case .strong(let children) = span { return children }
            return nil
        }.first

        #expect(strong != nil)
        #expect(strong?.contains { if case .emphasis = $0 { return true }; return false } == true)
        #expect(content.plainText == "A bold and italic run.")
    }

    @Test func underscoresInsideWordsAreNotEmphasis() {
        let document = MarkdownDocumentParser.parse("Call snake_case_name here.")

        guard case .paragraph(let content) = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(content.plainText == "Call snake_case_name here.")
        #expect(content.allSatisfy { if case .text = $0 { return true }; return false })
    }

    @Test func inlineCodeIsNotParsedAsMarkdown() {
        let document = MarkdownDocumentParser.parse("Use `**not bold**` here.")

        guard case .paragraph(let content) = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }
        let code = content.compactMap { span -> String? in
            if case .code(let value) = span { return value }
            return nil
        }.first
        #expect(code == "**not bold**")
    }

    @Test func nestedListsBecomeChildBlocks() {
        let markdown = """
        - Outer
            - Inner
        - Second
        """
        let document = MarkdownDocumentParser.parse(markdown)

        guard case .list(let list) = document.blocks[0] else {
            Issue.record("Expected a list")
            return
        }
        #expect(list.items.count == 2)
        #expect(list.items[0].content.plainText == "Outer")

        // The nested list must be a child of its item rather than a sibling —
        // this containment is what becomes PDF structure and EPUB nesting.
        guard case .list(let inner)? = list.items[0].children.first else {
            Issue.record("Expected a nested list inside the first item")
            return
        }
        #expect(inner.items[0].content.plainText == "Inner")
    }

    @Test func orderedListsKeepTheirStartingNumber() {
        let document = MarkdownDocumentParser.parse("5. Five\n6. Six")

        guard case .list(let list) = document.blocks[0] else {
            Issue.record("Expected a list")
            return
        }
        #expect(list.isOrdered)
        #expect(list.start == 5)
    }

    @Test func taskStateIsCaptured() {
        let document = MarkdownDocumentParser.parse("- [x] Done\n- [ ] Pending")

        guard case .list(let list) = document.blocks[0] else {
            Issue.record("Expected a list")
            return
        }
        #expect(list.items[0].taskState == .completed)
        #expect(list.items[1].taskState == .notCompleted)
    }

    @Test func tablesCaptureHeadersAndAlignment() {
        let markdown = """
        | Name | Count |
        | :--- | ----: |
        | Apple | 3 |
        """
        let document = MarkdownDocumentParser.parse(markdown)

        guard case .table(let table) = document.blocks[0] else {
            Issue.record("Expected a table")
            return
        }
        #expect(table.headers.count == 2)
        #expect(table.headers[0].plainText == "Name")
        #expect(table.rows.count == 1)
        #expect(table.rows[0][1].plainText == "3")
        #expect(table.alignment(forColumn: 0) == .leading)
        #expect(table.alignment(forColumn: 1) == .trailing)
    }

    @Test func imagesCaptureAlternativeText() {
        let document = MarkdownDocumentParser.parse("![A ghost](ghost.png)")

        guard case .paragraph(let content) = document.blocks[0],
              case .image(let image)? = content.first else {
            Issue.record("Expected an image")
            return
        }
        #expect(image.source == "ghost.png")
        #expect(image.alternativeText == "A ghost")
        #expect(!image.isDecorative)
    }

    @Test func emptyAltTextMarksAnImageDecorative() {
        let document = MarkdownDocumentParser.parse("![](divider.png)")

        guard case .paragraph(let content) = document.blocks[0],
              case .image(let image)? = content.first else {
            Issue.record("Expected an image")
            return
        }
        #expect(image.isDecorative)
    }

    @Test func tactileTitleClassifiesTheImageCaseInsensitively() {
        let document = MarkdownDocumentParser.parse(
            "![Raised map](map.svg \"TACTILE\")"
        )

        guard case .paragraph(let content) = document.blocks[0],
              case .image(let image)? = content.first else {
            Issue.record("Expected a tactile image")
            return
        }
        #expect(image.title == "TACTILE")
        #expect(image.isTactile)
        #expect(!image.isDecorative)
    }

    @Test func anUnrelatedImageTitleRemainsAnOrdinaryImage() {
        let document = MarkdownDocumentParser.parse(
            "![Photo](photo.jpg \"Figure one\")"
        )

        guard case .paragraph(let content) = document.blocks[0],
              case .image(let image)? = content.first else {
            Issue.record("Expected an image")
            return
        }
        #expect(image.title == "Figure one")
        #expect(!image.isTactile)
    }

    @Test func referenceLinksResolve() {
        let markdown = """
        See [the site][home].

        [home]: https://example.com
        """
        let document = MarkdownDocumentParser.parse(markdown)

        guard case .paragraph(let content) = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }
        let destination = content.compactMap { span -> String? in
            if case .link(let value, _) = span { return value }
            return nil
        }.first
        #expect(destination == "https://example.com")
    }

    @Test func blockQuotesNestTheirContent() {
        let document = MarkdownDocumentParser.parse("> ## Quoted heading\n> Body text")

        guard case .blockQuote(let children) = document.blocks[0] else {
            Issue.record("Expected a block quote")
            return
        }
        guard case .heading(let level, _) = children[0] else {
            Issue.record("Expected a heading inside the quote")
            return
        }
        #expect(level == 2)
        #expect(children.count == 2)
    }

    @Test func fencedCodeKeepsItsLanguageAndBody() {
        let document = MarkdownDocumentParser.parse("```swift\nlet x = 1\n```")

        guard case .codeBlock(let language, let code) = document.blocks[0] else {
            Issue.record("Expected a code block")
            return
        }
        #expect(language == "swift")
        #expect(code == "let x = 1")
    }

    @Test func hardBreaksBecomeLineBreaks() {
        let document = MarkdownDocumentParser.parse("First line  \nSecond line")

        guard case .paragraph(let content) = document.blocks[0] else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(content.contains { if case .lineBreak = $0 { return true }; return false })
    }
}
