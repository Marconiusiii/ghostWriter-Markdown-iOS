import Foundation
import Testing
@testable import ghostWriter

struct CompilationFormatTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII=")!
    private struct Translator: BrailleTranslator {
        func translate(_ input: BrailleTranslationInput, grade: BrailleGrade) async throws -> String {
            String(repeating: "⠁", count: max(1, input.text.count))
        }
    }
    private func fixture(_ root: URL) throws -> [WordCompilationSource] {
        try (1...2).map { index in
            let directory = root.appendingPathComponent("source-\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("image.png"))
            let text = "# Chapter \(index)\n\n[Local heading](#heading-1)\n\n1. Item \(index)\n\n| A | B |\n| --- | --- |\n| X | Y |\n\n![Image \(index)](image.png)"
            return WordCompilationSource(title: "filename-\(index)", markdown: text, sourceDirectory: directory, language: index == 1 ? "en-US" : "es-MX", sourceURL: directory.appendingPathComponent("filename-\(index).md"))
        }
    }
    private func part(_ data: Data, _ name: String) throws -> String {
        let entries = try WordPackage.entries(from: data, paths: [name])
        return String(decoding: try #require(entries[name]), as: UTF8.self)
    }

    @Test func formatChoicesRemainIndependent() {
        var settings = CompilationExportSettings()
        settings.preservesHeadings = false
        settings.startsOnNewPages = false
        settings.format = .pdf
        #expect(settings.preservesHeadings)
        #expect(settings.startsOnNewPages)
        settings.startsOnNewPages = false
        settings.format = .word
        #expect(!settings.preservesHeadings && !settings.startsOnNewPages)
        settings.format = .pdf
        #expect(settings.preservesHeadings && !settings.startsOnNewPages)
        #expect(CompilationFormat.allCases.count == 9)
        #expect(!CompilationFormat.plainText.supportsHeadingOptions)
        #expect(!CompilationFormat.epub.supportsPageBreaks)
    }

    @Test func preparedDocumentsKeepAssetIdentityLanguageHeadingsAndLists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = try fixture(root)
        let document = try CompilationDocument.prepare(sources: sources, preservesHeadings: false, assetDirectory: root)
        #expect(document.compilationSections.map(\.language) == ["en-US", "es-MX"])
        #expect(document.headings().map(\.level) == [1, 2])
        #expect(document.headings().map { $0.content.plainText } == ["Chapter 1", "Chapter 2"])
        #expect(Set(document.images.map(\.source)).count == 2)
        for image in document.images { #expect(try Data(contentsOf: root.appendingPathComponent(image.source)) == png) }
        #expect(document.blocks.filter { if case .list = $0 { return true }; return false }.count == 2)
        let markdown = CompilationMarkdownWriter.write(document)
        #expect(markdown.contains("#heading-2"))
        #expect(markdown.contains("id=\"heading-2\""))
        #expect(markdown.contains("\n\n<a id=\"document-2\""))
        let text = PlainTextWriter.write(title: "Output filename", markdown: "", preparedDocument: document)
        #expect(text.contains("Chapter 1") && text.contains("Chapter 2"))
        #expect(!text.contains("Output filename"))
    }

    @Test func epubAndHTMLKeepSectionsNavigationAndEmbeddedImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try CompilationDocument.prepare(sources: fixture(root), preservesHeadings: false, assetDirectory: root)
        let data = try EPUBWriter.write(title: "Combined book", markdown: "", sourceDirectory: root, preparedDocument: document)
        let content = try part(data, "OEBPS/content.xhtml")
        let nav = try part(data, "OEBPS/nav.xhtml")
        #expect(content.contains("id=\"document-2\""))
        #expect(content.contains("xml:lang=\"es-MX\""))
        #expect(content.contains("<h2 id=\"heading-2\">Chapter 2</h2>"))
        #expect(!content.contains(">Combined book</h1>"))
        #expect(nav.contains("content.xhtml#heading-2"))
        let html = EPUBWriter.compilationHTML(title: "Combined book", document: document, sourceDirectory: root, language: "en-US")
        #expect(html.components(separatedBy: "src=\"data:image/png;base64,").count - 1 == 2)
        #expect(!html.contains("href=\"style.css\""))
        #expect(html.contains("alt=\"Image 2\""))
    }

    @Test func brailleWritersAcceptCompilationWithoutAnExtraOutputTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try CompilationDocument.prepare(sources: fixture(root), preservesHeadings: false, assetDirectory: root)
        let metadata = EBrailleMetadata(creator: "Author", transcriber: "Producer", copyrightYear: "2026")
        let data = try await EBrailleWriter.write(title: "Book", markdown: "", metadata: metadata, translator: Translator(), sourceDirectory: root, preparedDocument: document)
        let content = try part(data, "content.xhtml")
        #expect(content.contains("id=\"document-2\""))
        #expect(content.contains("<h2 id=\"heading-2\">"))
        let brf = try await BRFWriter.write(markdown: "", title: "Book", grade: .grade2, translator: Translator(), preparedDocument: document)
        #expect(!brf.isEmpty)
    }

    @Test func powerPointStartsEachSourceOnItsOwnSlideAndRetainsLanguage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = [WordCompilationSource(title: "one", markdown: "# One\nText", language: "en-US"), WordCompilationSource(title: "two", markdown: "# Two\nTexto\n[First](#heading-1)", language: "es-MX")]
        let document = try CompilationDocument.prepare(sources: sources, preservesHeadings: true, assetDirectory: root)
        let data = try PowerPointWriter.write(title: "Book", markdown: "", preparedDocument: document)
        let slide = try part(data, "ppt/slides/slide2.xml")
        #expect(slide.contains(">Two</a:t>"))
        #expect(slide.contains("lang=\"es-MX\""))
        #expect(slide.contains(">Texto"))
        let relationships = try part(data, "ppt/slides/_rels/slide2.xml.rels")
        #expect(relationships.contains("Target=\"slide2.xml\""))
        #expect(slide.contains("ppaction://hlinksldjump"))
    }

    @Test func linkedAttachmentsAndCrossDocumentLinksSurviveEPUBPackaging() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("Attachment".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let sources = [
            WordCompilationSource(title: "first", markdown: "# First\n[Next](second.md#heading-1)\n\n[Notes](notes.txt)", sourceDirectory: root, language: "en-US", sourceURL: root.appendingPathComponent("first.md")),
            WordCompilationSource(title: "second", markdown: "## Subheading\nBody", sourceDirectory: root, language: "en-US", sourceURL: root.appendingPathComponent("second.md"))
        ]
        let output = root.appendingPathComponent("output")
        let document = try CompilationDocument.prepare(sources: sources, preservesHeadings: true, assetDirectory: output)
        let data = try EPUBWriter.write(title: "Book", markdown: "", sourceDirectory: output, preparedDocument: document)
        let html = try part(data, "OEBPS/content.xhtml")
        #expect(html.contains("href=\"#heading-3\""))
        let asset = try #require(document.compilationLinkedAssets.first)
        #expect(try part(data, "OEBPS/" + asset) == "Attachment")
        #expect(try part(data, "OEBPS/content.opf").contains(asset))
    }

    #if canImport(UIKit)
    @Test func fileWriterCreatesEachNonBrailleFormatAndPackagesMarkdownAssets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = try fixture(root)
        for format in CompilationFormat.allCases where format != .eBraille && format != .brf {
            var settings = CompilationExportSettings()
            settings.format = format
            let url = try await CompilationFileWriter.write(title: "Compilation", sources: sources, settings: settings)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            #expect(url.pathExtension == (format == .markdown ? "zip" : format.fileExtension))
            #expect(try Data(contentsOf: url).count > 0)
        }
    }

    @Test func pdfCompilationUsesPageBoundariesAndOneHeadingOneWhenShifted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = [WordCompilationSource(title: "one", markdown: "# One\nText", language: "en-US"), WordCompilationSource(title: "two", markdown: "# Two\nTexto", language: "es-MX")]
        let document = try CompilationDocument.prepare(sources: sources, preservesHeadings: false, assetDirectory: root)
        let data = try TaggedPDFWriter.write(title: "Book", markdown: "", preparedDocument: document, startsDocumentsOnNewPages: true)
        let decoded = String(decoding: data, as: UTF8.self)
        #expect(decoded.contains("/H1") && decoded.contains("/H2"))
        #expect(decoded.contains("/Sect"))
        #expect(decoded.contains("/Lang"))
    }
    #endif

    @Test func cancellationStopsPreparation() async {
        let task = Task.detached { () throws -> ExportDocument in
            withUnsafeCurrentTask { $0?.cancel() }
            return try CompilationDocument.prepare(sources: [WordCompilationSource(title: "One", markdown: "# One", language: "en-US")], preservesHeadings: true, assetDirectory: FileManager.default.temporaryDirectory)
        }
        do { _ = try await task.value; Issue.record("Cancelled preparation succeeded") }
        catch is CancellationError { }
        catch { Issue.record("Unexpected error: \(error)") }
    }
}
