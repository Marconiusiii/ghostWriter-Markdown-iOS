import Foundation
import Testing
@testable import ghostWriter

struct ThematicSeparatorTests {
    private let markdown = "# Chapter\n\nBefore\n\n---\n\nAfter"

    @Test func allDecorationsAreCenteredInPlainTextAndWord() throws {
        for style in ThematicSeparator.allCases {
            let plain = PlainTextWriter.write(title: "", markdown: markdown, thematicSeparator: style)
            let data = try MarkdownToWordConverter.convert(title: "Chapter", markdown: markdown, thematicSeparator: style)
            let parts = try WordPackage.entries(from: data, paths: ["word/document.xml"])
            let xml = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
            if let text = style.text {
                let centered = String(repeating: " ", count: (72 - text.count) / 2) + text
                #expect(plain.contains("\n" + centered + "\n"))
                #expect(xml.contains("<w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t xml:space=\"preserve\">" + text))
                #expect(PlainTextWriter.write(title: "", markdown: "---", thematicSeparator: style) == centered + "\n")
            } else {
                #expect(!plain.contains("---"))
                #expect(!xml.contains("<w:jc"))
            }
        }
    }

    @Test func protectsCodeAndHeadingUnderlines() {
        let source = "Section\n---\n\n```\n---\n```\n\n`---`\n\n---"
        let word = MarkdownToWordConverter.document(from: source, thematicSeparator: .spacedBullets)
        let paragraphs = word.blocks.compactMap { block -> WordParagraph? in
            if case .paragraph(let paragraph) = block { return paragraph }
            return nil
        }
        #expect(paragraphs.first?.headingLevel == 2)
        #expect(paragraphs.filter(\.isThematicSeparator).count == 1)
        #expect(paragraphs.contains { $0.isCodeBlock && $0.runs.first?.text == "---" })
        #expect(paragraphs.contains { $0.runs.contains { $0.inlineCode && $0.text == "---" } })
        let plain = PlainTextWriter.write(title: "", markdown: source, thematicSeparator: .spacedBullets)
        #expect(plain.components(separatedBy: "• • •").count == 2)
        #expect(plain.contains("Section\n-------"))
        #expect(plain.contains("    ---"))
    }

    @Test func compilationPreservesDecorationAndDocumentBoundary() throws {
        let sources = [WordCompilationSource(title: "Chapter", markdown: markdown, language: "en"),
                       WordCompilationSource(title: "Next", markdown: "# Next\n\nText", language: "en")]
        var options = WordExportOptions()
        options.startsDocumentsOnNewPages = false
        options.preservesHeadingStructure = false
        options.usesSmartPunctuation = true
        options.thematicSeparator = .spacedPeriods
        let document = try WordCompilation.document(sources: sources, options: options)
        let paragraphs = document.blocks.compactMap { block -> WordParagraph? in
            if case .paragraph(let paragraph) = block { return paragraph }
            return nil
        }
        #expect(paragraphs.filter(\.isThematicSeparator).map { $0.runs.map(\.text).joined() } == [". . ."])
        let next = try #require(paragraphs.firstIndex { $0.runs.map(\.text).joined() == "Next" })
        #expect(paragraphs[next].headingLevel == 2)
        #expect(paragraphs[next - 1].runs.isEmpty)
        #expect(!paragraphs[next - 1].isThematicSeparator)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiled = try CompilationDocument.prepare(sources: sources, preservesHeadings: false, assetDirectory: directory, includesImages: false, usesSmartPunctuation: true)
        let plain = PlainTextWriter.write(title: "Book", markdown: "", preparedDocument: compiled, thematicSeparator: .spacedPeriods)
        #expect(plain.components(separatedBy: ". . .").count == 2)
        #expect(!plain.contains("…"))
    }
}
