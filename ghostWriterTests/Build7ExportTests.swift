import Foundation
import Testing
@testable import ghostWriter

struct Build7ExportTests {
    private func xml(_ markdown: String, json: String) throws -> String {
        let theme = try WordExportTheme.decode(Data(json.utf8))
        let file = try MarkdownToWordConverter.convert(title: "Coffee", markdown: markdown, theme: theme)
        return String(decoding: try #require(WordPackage.entries(from: file, paths: ["word/document.xml"])["word/document.xml"]), as: UTF8.self)
    }

    @Test func openingPairKeepsBuiltInHeadingsAndOnlyFormatsOpeningPair() throws {
        let result = try xml("# Coffee\n\n## Subtitle\n\nText.\n\n## Section\n### Topic", json: #"{"version":1,"title":{"size":30},"subtitle":{"size":23}}"#)
        #expect(result.contains("w:pStyle w:val=\"Heading1\""))
        #expect(result.contains("w:pStyle w:val=\"Heading2\""))
        #expect(result.contains("w:pStyle w:val=\"Heading3\""))
        #expect(result.components(separatedBy: "w:sz w:val=\"46\"").count == 2)
        #expect(result.components(separatedBy: "w:sz w:val=\"60\"").count == 2)
        #expect(!result.contains("w:pStyle w:val=\"Title\""))
    }

    @Test(arguments: ["A paragraph.", "---", "![Image](photo.png)", "- Item", "```\ncode\n```", "<!-- comment -->", "[link]: https://example.org"])
    func interveningContentDisablesBothStyles(_ content: String) throws {
        let result = try xml("# Coffee\n\n\(content)\n\n## Subtitle", json: #"{"version":1,"title":{"size":30},"subtitle":{"size":23}}"#)
        #expect(!result.contains("w:sz w:val=\"60\""))
        #expect(!result.contains("w:sz w:val=\"46\""))
    }

    @Test(arguments: [#"{"version":1}"#, #"{"version":1,"title":{"size":30}}"#, #"{"version":1,"subtitle":{"size":23}}"#])
    func bothDefinitionsAreRequired(_ json: String) throws {
        let result = try xml("# Coffee\n## Subtitle", json: json)
        #expect(!result.contains("w:sz w:val=\"60\""))
        #expect(!result.contains("w:sz w:val=\"46\""))
    }

    @Test func authoredOpeningPairDoesNotGainAnExtraFilenameHeading() throws {
        let theme = try WordExportTheme.decode(Data(#"{"version":1,"title":{"size":30},"subtitle":{"size":23}}"#.utf8))
        let file = try MarkdownToWordConverter.convert(title: "Draft file", markdown: "# Coffee\n## Subtitle", theme: theme)
        let entries = try WordPackage.entries(from: file, paths: ["word/document.xml"])
        let result = String(decoding: try #require(entries["word/document.xml"]), as: UTF8.self)
        #expect(!result.contains("Draft file"))
        #expect(result.components(separatedBy: "w:pStyle w:val=\"Heading1\"").count == 2)
    }

    @Test func setextOpeningPairAndUnpairedTitleFollowSameRule() throws {
        let theme = #"{"version":1,"title":{"size":30},"subtitle":{"size":23}}"#
        let pair = try xml("Coffee\n======\n\nSubtitle\n--------\n\nText", json: theme)
        #expect(pair.contains("w:sz w:val=\"60\""))
        #expect(pair.contains("w:sz w:val=\"46\""))
        let unpaired = try xml("# Coffee\nText\n\n# Later\n## Pair", json: theme)
        #expect(!unpaired.contains("w:sz w:val=\"60\""))
        #expect(!unpaired.contains("w:sz w:val=\"46\""))
    }

    @Test func stylesheetBreakOverridesGlobalSetting() throws {
        let theme = try WordExportTheme.decode(Data(#"{"version":1,"thematicBreak":{"behavior":"separator","text":"A & B"}}"#.utf8))
        let file = try MarkdownToWordConverter.convert(title: "Coffee", markdown: "# Coffee\n\n---\n\nEnd", theme: theme, thematicSeparator: .none)
        let parts = try WordPackage.entries(from: file, paths: ["word/document.xml"])
        let result = String(decoding: try #require(parts["word/document.xml"]), as: UTF8.self)
        #expect(result.contains("A &amp; B"))
        let page = try xml("# Coffee\n\n---\n\nEnd", json: #"{"version":1,"thematicBreak":{"behavior":"pageBreak"}}"#)
        #expect(page.contains("<w:pageBreakBefore/>"))
        let omitted = try xml("# Coffee\n\n---\n\nEnd", json: #"{"version":1,"thematicBreak":{"behavior":"omit"}}"#)
        #expect(!omitted.contains("<w:pageBreakBefore/>"))
    }

    @Test func headersFootersAndPaginationHaveCompletePackageRelationships() throws {
        let theme = try WordExportTheme.decode(Data(#"{"version":1,"body":{"firstLineIndent":24,"pageBreakAfter":true},"headings":{"1":{"pageBreakBefore":true,"keepWithNext":true}},"header":{"text":"A & B","alignment":"right"},"footer":{"text":"Page ","pageNumber":true,"alignment":"center"},"differentFirstPage":true}"#.utf8))
        let file = try MarkdownToWordConverter.convert(title: "Coffee", markdown: "# Coffee\nText", theme: theme)
        let paths: Set<String> = ["word/document.xml", "word/styles.xml", "word/header.xml", "word/headerFirst.xml", "word/footer.xml", "word/footerFirst.xml", "word/_rels/document.xml.rels", "[Content_Types].xml"]
        let entries = try WordPackage.entries(from: file, paths: paths)
        #expect(entries.count == paths.count)
        for (path, contents) in entries { _ = try WordXMLTreeParser.parse(contents, partName: path) }
        let document = String(decoding: try #require(entries["word/document.xml"]), as: UTF8.self)
        #expect(document.contains("<w:titlePg/>"))
        #expect(document.contains("w:type=\"first\" r:id=\"rIdheaderFirst\""))
        #expect(document.contains("w:br w:type=\"page\""))
        let footer = String(decoding: try #require(entries["word/footer.xml"]), as: UTF8.self)
        #expect(footer.contains("w:instr=\" PAGE \""))
        #expect(footer.contains("Page "))
        let styles = String(decoding: try #require(entries["word/styles.xml"]), as: UTF8.self)
        #expect(styles.contains("w:firstLine=\"480\""))
        #expect(styles.contains("<w:keepNext w:val=\"1\"/>"))
        let relationships = String(decoding: try #require(entries["word/_rels/document.xml.rels"]), as: UTF8.self)
        #expect(relationships.contains("Target=\"footer.xml\""))
    }

    @Test func compilationAppliesPairOnlyToFirstSourceAndPreservedHeadings() throws {
        let theme = try WordExportTheme.decode(Data(#"{"version":1,"title":{"size":30},"subtitle":{"size":23}}"#.utf8))
        let source = WordCompilationSource(title: "Coffee", markdown: "# Coffee\n## Subtitle", language: "en")
        var options = WordExportOptions(theme: theme)
        let model = try WordCompilation.document(sources: [source, source], options: options)
        let roles = model.blocks.compactMap { block -> String? in
            if case .paragraph(let p) = block { return p.openingStyle }
            return nil
        }
        #expect(roles == ["title", "subtitle"])
        options.preservesHeadingStructure = false
        let shifted = try WordCompilation.document(sources: [source], options: options)
        #expect(shifted.blocks.allSatisfy { if case .paragraph(let p) = $0 { return p.openingStyle == nil }; return true })
    }

    @Test func namedChoicesValidateAndRespectDeletedLargePrintExample() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try await WordStylesheetLoader.choices(in: root)
        #expect(initial.map(\.filename) == ["Large Print.json"])
        let directory = WordStylesheetLoader.directory(in: root)
        try Data(#"{"version":1}"#.utf8).write(to: directory.appendingPathComponent("Essay.json"))
        try Data(#"{"version":1,"unknown":true}"#.utf8).write(to: directory.appendingPathComponent("Broken.json"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("Large Print.json"))
        let choices = try await WordStylesheetLoader.choices(in: root)
        #expect(choices.count == 2)
        #expect(choices.first { $0.filename == "Essay.json" }?.error == nil)
        #expect(choices.first { $0.filename == "Broken.json" }?.error != nil)
        do { _ = try await WordStylesheetLoader.loadSelection("Missing.json", in: root); Issue.record("Missing selection silently accepted") }
        catch { }
        #expect(try WordExportTheme.decode(Data(WordStylesheetLoader.largePrint.utf8)).title == nil)
    }

    @Test(arguments: [#"{"version":1,"body":{"firstLineIndent":-1}}"#, #"{"version":1,"header":{"alignment":"justify"}}"#, #"{"version":1,"thematicBreak":{"behavior":"separator"}}"#, #"{"version":1,"footer":{"pageNumber":"yes"}}"#])
    func rejectsInvalidNewProperties(_ json: String) {
        #expect(throws: WordThemeError.self) { try WordExportTheme.decode(Data(json.utf8)) }
    }

    @MainActor @Test func inheritedExclusionsDetermineStatisticsWithoutNewPreferences() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = URL(fileURLWithPath: "/Library")
        let folder = root.appendingPathComponent("Book")
        let file = folder.appendingPathComponent("Notes.md")
        let metadata = DocumentLibraryMetadataStore(defaults: defaults)
        metadata.useLibraryRoot(root)
        #expect(metadata.isIncludedInStatistics(file))
        metadata.toggleDefaultInclusion(for: folder)
        #expect(!metadata.isIncludedInStatistics(file))
        metadata.toggleDefaultInclusion(for: file)
        metadata.toggleDefaultInclusion(for: folder)
        #expect(!metadata.isIncludedInStatistics(file))
        metadata.toggleDefaultInclusion(for: file)
        #expect(metadata.isIncludedInStatistics(file))
    }

    @Test func sentenceCountsHandleEmptySourceAndNormalProse() throws {
        #expect(try FolderTextCount.count("").sentences == 0)
        #expect(try FolderTextCount.count("---\n***").sentences == 0)
        #expect(try FolderTextCount.count("Coffee is ready. Would you like some? Yes!").sentences == 3)
    }
}
