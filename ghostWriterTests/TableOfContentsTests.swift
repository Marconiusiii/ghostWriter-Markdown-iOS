import Foundation
import PDFKit
import Testing
@testable import ghostWriter

struct TableOfContentsTests {
    @Test func htmlContentsHasHeadingAndNestedListsAfterTitle() throws {
        let html = MarkdownRenderer.html(from: "# Book\n\n## Chapter & one\n\n#### Deep\n\n## Chapter & one", includesTableOfContents: true)
        #expect(html.hasPrefix("<h1 id=\"heading-1\">Book</h1><details><summary><h2>Table of Contents</h2></summary><ul>"))
        #expect(html.contains("<li><a href=\"#heading-2\">Chapter &amp; one</a><ul><li><a href=\"#heading-3\">Deep</a></li></ul></li>"))
        #expect(html.contains("href=\"#heading-4\""))
        #expect(!html.contains("href=\"#heading-1\""))
        #expect(!html.contains("aria-"))
        #expect(!html.contains("<details open"))
        #expect(html.contains("</ul></details><h2 id=\"heading-2\">"))
        let parser = XMLParser(data: Data(("<root>" + html + "</root>").utf8))
        #expect(parser.parse())
    }

    @Test func emptyHeadingsAndCodeDoNotCreateBrokenHTMLLinks() {
        let html = MarkdownRenderer.html(from: "# Book\n\n##\n\n```\n# Literal\n```\n\n## End", includesTableOfContents: true)
        #expect(html.contains("href=\"#heading-2\">End</a>"))
        #expect(html.contains("<h2 id=\"heading-2\">End</h2>"))
        #expect(!html.contains(">Literal</a>"))
        #expect(!html.contains("href=\"#heading-3\""))
    }

    @Test func contentsOffAndTitleOnlyDoNotAddContents() {
        let markdown = "# Book\n\n## Chapter"
        #expect(!MarkdownRenderer.html(from: markdown).contains("Table of Contents"))
        #expect(!MarkdownRenderer.html(from: "# Book\n\nBody", includesTableOfContents: true).contains("Table of Contents"))
    }

    @Test func compilationHTMLUsesFinalHierarchyAndUniqueDestinations() async throws {
        let sources = [WordCompilationSource(title: "Book", markdown: "# Book\n\n## Repeated", language: "en"),
                       WordCompilationSource(title: "Next", markdown: "# Next\n\n## Repeated", language: "es")]
        var options = CompilationExportSettings()
        options.format = .html
        options.preservesHeadings = false
        options.includesTableOfContents = true
        let url = try await CompilationFileWriter.write(title: "Compilation", sources: sources, settings: options)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(html.contains("<details><summary><h2>Table of Contents</h2></summary><ul>"))
        #expect(html.contains("<h2 id=\"heading-3\">Next</h2>"))
        #expect(html.contains("href=\"#heading-3\">Next</a><ul><li><a href=\"#heading-4\">Repeated</a>"))
        #expect(html.contains("lang=\"es\""))
    }

    @Test func compilationWordContentsUsesShiftedHeadingLevels() throws {
        let sources = [WordCompilationSource(title: "Book", markdown: "# Book\n\n## First section", language: "en"),
                       WordCompilationSource(title: "Chapter", markdown: "# Chapter\n\n## Last section", language: "en")]
        for preserve in [true, false] {
            var options = WordExportOptions()
            options.preservesHeadingStructure = preserve
            options.theme = try WordExportTheme.decode(Data(#"{"version":1,"tableOfContents":{"maximumLevel":2}}"#.utf8))
            let data = try WordCompilation.write(title: "Book", sources: sources, options: options)
            let parts = try WordPackage.entries(from: data, paths: ["word/document.xml"])
            let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
            #expect(xml.contains("w:anchor=\"GWHeading3\""))
            #expect(xml.contains("w:anchor=\"GWHeading4\"") == preserve)
            #expect(!xml.contains("w:anchor=\"GWHeading1\""))
        }
    }

    @Test func compilationPDFContentsLinksReachTheirSourceSections() async throws {
        let sources = [WordCompilationSource(title: "Book", markdown: "# Book\n\n## First section\n\nText", language: "en"),
                       WordCompilationSource(title: "Chapter", markdown: "# Chapter\n\n## Last section\n\nText", language: "en")]
        var options = CompilationExportSettings()
        options.format = .pdf
        options.includesTableOfContents = true
        options.preservesHeadings = false
        let url = try await CompilationFileWriter.write(title: "Book", sources: sources, settings: options)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pdf = try #require(PDFDocument(url: url))
        let destinations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
            .compactMap { ($0.action as? PDFActionGoTo)?.destination }
        #expect(destinations.count == 3)
        #expect(destinations.last?.page?.string?.contains("Last section") == true)
        #expect(pdf.page(at: 0)?.string?.contains("First section, page 2") == true)
        #expect(pdf.page(at: 0)?.string?.contains("Last section, page 3") == true)
    }

    @Test func singleFileWritersUseContentsOption() async throws {
        for format: EditorView.EditorShareFormat in [.html, .pdf] {
            let url = try await EditorShareFileWriter.write(format: format, title: "Book", fileName: "Book", markdown: "# Book\n\n## Chapter", sourceDirectory: nil, includesTableOfContents: true)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            if format == .html {
                #expect(try String(contentsOf: url, encoding: .utf8).contains("<details><summary><h2>Table of Contents</h2></summary><ul>"))
            } else {
                #expect(PDFDocument(url: url)?.string?.contains("Table of Contents") == true)
            }
        }
    }

    @Test func compilationContentsPreferencesAreIndependentAndOffInitially() {
        var settings = CompilationExportSettings()
        settings.format = .html
        #expect(!settings.includesTableOfContents)
        settings.includesTableOfContents = true
        settings.format = .pdf
        #expect(!settings.includesTableOfContents)
        settings.format = .html
        #expect(settings.includesTableOfContents)
    }

    @Test func wordContentsKeepsNativeFieldsAndExcludesOpeningPair() throws {
        let theme = try WordExportTheme.decode(Data(#"{"version":1,"title":{},"subtitle":{},"tableOfContents":{"maximumLevel":2}}"#.utf8))
        let data = try MarkdownToWordConverter.convert(title: "Filename", markdown: "# Book\n\n## Subtitle\n\n# Chapter\n\n## Repeated\n\n### Too deep\n\n## Repeated", theme: theme)
        let parts = try WordPackage.entries(from: data, paths: ["word/document.xml", "word/settings.xml"])
        let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
        #expect(XMLParser(data: Data(xml.utf8)).parse())
        #expect(xml.contains("TOC \\o &quot;1-2&quot; \\h \\b GWContentsBody"))
        #expect(xml.contains("w:anchor=\"GWHeading3\""))
        #expect(xml.contains("w:anchor=\"GWHeading4\""))
        #expect(xml.contains("w:anchor=\"GWHeading6\""))
        #expect(!xml.contains("w:anchor=\"GWHeading1\""))
        #expect(!xml.contains("w:anchor=\"GWHeading2\""))
        #expect(!xml.contains("w:anchor=\"GWHeading5\""))
        #expect(xml.contains(" PAGEREF GWHeading3 \\h "))
        #expect(xml.contains("w:name=\"GWContentsBody\""))
        #expect(xml.contains("w:pStyle w:val=\"Heading1\""))
        #expect(String(decoding: try #require(parts["word/settings.xml"]), as: UTF8.self).contains("updateFields"))
    }

    @Test func wordContentsNoPagesAndOrdinaryH2IsNotSubtitle() throws {
        let theme = try WordExportTheme.decode(Data(#"{"version":1,"tableOfContents":{"pageNumbers":false,"pageBreakAfter":false}}"#.utf8))
        let data = try MarkdownToWordConverter.convert(title: "Book", markdown: "# Book\n\n## Chapter", theme: theme)
        let parts = try WordPackage.entries(from: data, paths: ["word/document.xml"])
        let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
        #expect(xml.contains("w:anchor=\"GWHeading2\""))
        #expect(xml.contains(" \\n "))
        #expect(!xml.contains("PAGEREF"))
        #expect(!xml.contains("w:type=\"page\""))
    }

    @Test func rejectsInvalidWordContentsSettings() {
        for fragment in [#"{"maximumLevel":7}"#, #"{"minimumLevel":4,"maximumLevel":2}"#, #"{"title":""}"#, #"{"pageNumbers":"yes"}"#, #"{"unknown":true}"#, "null"] {
            #expect(throws: (any Error).self) { try WordExportTheme.decode(Data(("{\"version\":1,\"tableOfContents\":" + fragment + "}").utf8)) }
        }
    }

    @Test func pdfContentsPageReferencesMatchFinalHeadingPages() throws {
        var markdown = "# Book\n\n"
        for chapter in 1...45 {
            markdown += "## ChapterNumber\(chapter)End\n\n" + String(repeating: "Some body text for the chapter. ", count: 25) + "\n\n"
        }
        let data = try TaggedPDFWriter.write(title: "Book", markdown: markdown, includesTableOfContents: true)
        let pdf = try #require(PDFDocument(data: data))
        let texts = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
        #expect(texts[0].contains("Table of Contents"))
        #expect(pdf.pageCount > 5)
        for chapter in [1, 20, 45] {
            let label = "ChapterNumber\(chapter)End"
            let page = try #require(texts.lastIndex { $0.contains(label) }) + 1
            #expect(texts.joined(separator: "\n").contains(label + ", page " + String(page)))
        }
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains("/StructTreeRoot"))
        #expect(raw.contains("/S /L"))
        #expect(raw.contains("/Subtype /Link"))
        let destinations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
            .compactMap { ($0.action as? PDFActionGoTo)?.destination }
        #expect(try TaggedPDFWriterTests.checkLinkAssociations(data) == 45)
        #expect(destinations.count == 45)
        for (index, destination) in destinations.enumerated() {
            #expect(destination.page?.string?.contains("ChapterNumber\(index + 1)End") == true)
        }
    }
}
