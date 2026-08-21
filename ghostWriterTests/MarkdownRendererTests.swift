//
//  MarkdownRendererTests.swift
//  ghostWriterTests
//
//  Focused regression coverage for semantic and safety-critical renderer output.
//

import Foundation
import Testing
@testable import ghostWriter

struct MarkdownRendererTests {

    @Test func rendersTwoTrailingSpacesAsAHardBreak() {
        let html = MarkdownRenderer.html(from: "First line  \nSecond line")
        #expect(html == "<p>First line<br>Second line</p>")
    }

    @Test func rendersBackslashAsAHardBreak() {
        let html = MarkdownRenderer.html(from: "First line\\\nSecond line")
        #expect(html == "<p>First line<br>Second line</p>")
    }

    @Test func escapesRawHTMLRatherThanExecutingIt() {
        let html = MarkdownRenderer.html(from: "<script>alert('no')</script>")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test func rendersSemanticHeadingListAndTableElements() {
        let markdown = """
        ## Features

        - One
        - Two

        | Name | Value |
        | --- | --- |
        | Alpha | 1 |
        """
        let html = MarkdownRenderer.html(from: markdown)

        #expect(html.contains("<h2>Features</h2>"))
        #expect(html.contains("<ul><li>One</li><li>Two</li></ul>"))
        #expect(html.contains("<th scope=\"col\">Name</th>"))
        #expect(html.contains("<tbody><tr><td>Alpha</td><td>1</td></tr></tbody>"))
    }

    @Test func rendersImageAlternativeText() {
        let html = MarkdownRenderer.html(
            from: "![A ghost writing at a desk](https://example.com/ghost.png)"
        )
        #expect(
            html.contains(
                "<img src=\"https://example.com/ghost.png\" alt=\"A ghost writing at a desk\">"
            )
        )
    }

    @Test func tactileGraphicDescriptionRemainsReadableBesideRemoteImage() {
        let html = MarkdownRenderer.html(
            from: "![A cute owl](https://marconius.com/svg/imageFiles/hooty.svg \"tactile\")"
        )

        #expect(html.contains("<figure class=\"tactile-graphic\">"))
        #expect(html.contains("src=\"https://marconius.com/svg/imageFiles/hooty.svg\""))
        #expect(html.contains("alt=\"\" title=\"tactile\""))
        #expect(html.contains("<figcaption>Tactile graphic: A cute owl</figcaption>"))
        #expect(html.components(separatedBy: "A cute owl").count == 2)
    }

    @Test func rendersTaskStatesWithoutPlatformCheckboxControls() {
        let html = MarkdownRenderer.html(
            from: "- [ ] Draft document\n- [x] Share document"
        )

        #expect(html.contains("<span class=\"task-status\">Not completed:</span>"))
        #expect(html.contains("<span class=\"task-status\">Completed:</span>"))
        #expect(html.contains("class=\"task-indicator completed\""))
        #expect(!html.contains("<input"))
        #expect(!html.contains("aria-"))
    }

    @Test func keepsMarkdownInsideCodeLiteral() {
        let html = MarkdownRenderer.html(from: "`**not bold**`")
        #expect(html == "<p><code>**not bold**</code></p>")
    }

    @Test func rendersCombinedNestedAndUnderlinedFormatting() {
        let html = MarkdownRenderer.html(
            from: "***Both***, *italic **with bold** text*, **bold *with italic* text**, and <u>underlined **bold** text</u>."
        )

        #expect(html.contains("<strong><em>Both</em></strong>"))
        #expect(html.contains("<em>italic <strong>with bold</strong> text</em>"))
        #expect(html.contains("<strong>bold <em>with italic</em> text</strong>"))
        #expect(html.contains("<u>underlined <strong>bold</strong> text</u>"))
    }

    @Test func underlineSupportDoesNotEnableOtherRawHTML() {
        let html = MarkdownRenderer.html(
            from: "<u>kept</u> <script>alert('no')</script>"
        )

        #expect(html.contains("<u>kept</u>"))
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test func intrawordUnderscoresRemainLiteral() {
        let html = MarkdownRenderer.html(from: "snake_case_name")
        #expect(html == "<p>snake_case_name</p>")
    }

    @Test func escapedMarkdownPunctuationRemainsLiteral() {
        let html = MarkdownRenderer.html(from: #"\*literal asterisks\* and \[brackets\]"#)

        #expect(html == "<p>*literal asterisks* and [brackets]</p>")
    }

    @Test func unsafeLinkSchemesBecomeOrdinaryText() {
        let html = MarkdownRenderer.html(
            from: "[Unsafe](javascript:location='https://example.com') and [Safe](https://example.com)"
        )

        #expect(!html.contains("javascript:"))
        #expect(html.contains("Unsafe"))
        #expect(html.contains("<a href=\"https://example.com\">Safe</a>"))
    }

    @Test func complexReferenceLinkUsesTheSharedInlineParser() {
        let html = MarkdownRenderer.html(
            from: "[A [nested] label][destination]\n\n[destination]: https://example.com"
        )

        #expect(html.contains("<a href=\"https://example.com\">A [nested] label</a>"))
    }

    @Test func titleIsAVisibleLevelOneHeadingUnlessTheDocumentAlreadyStartsWithIt() {
        let inserted = MarkdownRenderer.html(from: "## Notes\n\nBody", title: "Notes")
        let retained = MarkdownRenderer.html(from: "# Notes\n\nBody", title: "Notes")

        #expect(inserted.hasPrefix("<h1>Notes</h1><h2>Notes</h2>"))
        #expect(retained.components(separatedBy: "<h1>Notes</h1>").count == 2)
    }

    @Test func orderedAndNestedListsRetainTheirStructure() {
        let html = MarkdownRenderer.html(
            from: "3. Third\n  - Nested\n4. Fourth"
        )

        #expect(html.contains("<ol start=\"3\">"))
        #expect(html.contains("<li>Third<ul><li>Nested</li></ul></li>"))
        #expect(html.contains("<li>Fourth</li>"))
    }
}
