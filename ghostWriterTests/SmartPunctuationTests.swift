import Foundation
import Testing
@testable import ghostWriter

struct SmartPunctuationTests {
    private func convert(_ text: String) -> String {
        SmartPunctuation.convert([.init(text: text)])[0]
    }

    @Test func quotationsApostrophesAndMeasurements() {
        #expect(convert("\"Hello,\" she said. Don't stop.") == "“Hello,” she said. Don’t stop.")
        #expect(convert("\"She said 'hello'.\"") == "“She said ‘hello’.”")
        #expect(convert("'tis the '90s; writers' books") == "’tis the ’90s; writers’ books")
        #expect(convert("6' 2\" and 12\" wide") == "6' 2\" and 12\" wide")
        #expect(convert("\"42\" and '42'") == "“42” and ‘42’")
        #expect(convert("“Existing” and don’t change — or ...") == "“Existing” and don’t change — or ...")
    }

    @Test func formattingAndProtectedContent() throws {
        let original: [ExportInline] = [.text("\"Don't "), .strong([.text("stop")]), .text(".\" "), .code("'literal'"), .text(" "), .link(destination: "https://example.org/'path'", content: [.text("\"Link\"")])]
        let result = SmartPunctuation.inlines(original)
        #expect(result == [.text("“Don’t "), .strong([.text("stop")]), .text(".” "), .code("'literal'"), .text(" "), .link(destination: "https://example.org/'path'", content: [.text("“Link”")])])
        #expect(convert("Visit https://example.org/'path' now") == "Visit https://example.org/'path' now")
        #expect(try SmartPunctuation.blocks([.codeBlock(language: nil, code: "\"literal\"")]) == [.codeBlock(language: nil, code: "\"literal\"")])
    }

    @Test func compilationIsOptInAndKeepsSourceUnchanged() throws {
        let source = WordCompilationSource(title: "filename", markdown: "# \"Title\"\n\nDon't **stop**.\n\n`\"code\"`\n\n| Header |\n| --- |\n| 'Text' |", language: "en")
        let root = FileManager.default.temporaryDirectory
        let plain = try CompilationDocument.prepare(sources: [source], preservesHeadings: true, assetDirectory: root)
        let smart = try CompilationDocument.prepare(sources: [source], preservesHeadings: true, assetDirectory: root, usesSmartPunctuation: true)
        #expect(plain.compilationSections[0].title == "\"Title\"")
        #expect(smart.compilationSections[0].title == "“Title”")
        #expect(smart.blocks.contains(.paragraph([.text("Don’t "), .strong([.text("stop")]), .text(".")])))
        #expect(CompilationMarkdownWriter.write(smart).contains("‘Text’"))
        #expect(source.markdown.contains("Don't"))
        var settings = CompilationExportSettings()
        #expect(!settings.usesSmartPunctuation)
        settings.usesSmartPunctuation = true
        for format in CompilationFormat.allCases {
            settings.format = format
            #expect(settings.usesSmartPunctuation)
        }
    }

    @Test func wordPreservesRunsCodeAndParagraphBoundaries() throws {
        let source = WordCompilationSource(title: "Title", markdown: "# \"Title\"\n\n\"Don't **stop**.\"\n\n`\"code\"`\n\n```\n\"literal\"\n```", language: "en")
        var options = WordExportOptions()
        let unchanged = try WordCompilation.document(sources: [source], options: options)
        options.usesSmartPunctuation = true
        let smart = try WordCompilation.document(sources: [source], options: options)
        #expect(unchanged.blocks.count == smart.blocks.count)
        let paragraphs = smart.blocks.compactMap { block -> WordParagraph? in
            if case .paragraph(let p) = block { return p }; return nil
        }
        #expect(paragraphs.contains { $0.runs.map(\.text).joined() == "“Don’t stop.”" })
        #expect(paragraphs.flatMap(\.runs).contains { $0.bold && $0.text == "stop" })
        #expect(paragraphs.flatMap(\.runs).contains { $0.inlineCode && $0.text == "\"code\"" })
        #expect(paragraphs.contains { $0.isCodeBlock && $0.runs.map(\.text).joined().contains("\"literal\"") })
    }
}
