//
//  ShareItemBuilderTests.swift
//  ghostWriterTests
//
//  Verifies that shared files contain the promised format and that HTML is a
//  complete standalone document rather than a fragment or plain Markdown.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ghostWriter

struct ShareItemBuilderTests {

    @Test func htmlShareIsACompleteRenderedDocument() throws {
        let url = try ShareItemBuilder.makeFile(
            title: "Accessible Notes",
            markdown: "## Introduction\n\nThis is **important**.",
            format: .html
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let html = try String(contentsOf: url, encoding: .utf8)

        #expect(url.pathExtension == "html")
        #expect(UTType(filenameExtension: url.pathExtension) == .html)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<head>"))
        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(html.contains("<meta name=\"viewport\""))
        #expect(html.contains("<title>Accessible Notes</title>"))
        #expect(html.contains("<main>"))
        #expect(!html.contains("<h1 class=\"document-title\">"))
        #expect(html.contains("<h2>Introduction</h2>"))
        #expect(html.contains("<strong>important</strong>"))
        #expect(html.contains("</main>"))
        #expect(html.contains("</html>"))
    }

    @Test func htmlShareEscapesTheDocumentTitle() throws {
        let html = ShareItemBuilder.contents(
            title: "Notes <Draft>",
            markdown: "Body",
            format: .html
        )

        #expect(html.contains("<title>Notes &lt;Draft&gt;</title>"))
        #expect(!html.contains(">Notes &lt;Draft&gt;</h1>"))
        #expect(!html.contains("<title>Notes <Draft></title>"))
    }

    @Test func emptyHTMLShareStillHasReadableContent() {
        let html = ShareItemBuilder.contents(
            title: "Empty Note",
            markdown: "",
            format: .html
        )

        #expect(!html.contains("<h1"))
        #expect(html.contains("<p class=\"empty-state\">This document is empty.</p>"))
    }

    @Test func textFormatsRemainUnrendered() {
        let markdown = "# Literal Markdown"

        #expect(
            ShareItemBuilder.contents(
                title: "Note",
                markdown: markdown,
                format: .markdown
            ) == markdown
        )
        #expect(
            ShareItemBuilder.contents(
                title: "Note",
                markdown: markdown,
                format: .plainText
            ) == markdown
        )
    }
}
