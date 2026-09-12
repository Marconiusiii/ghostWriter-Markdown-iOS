import Foundation

nonisolated struct WordExportOptions: Equatable, Sendable {
    var thematicSeparator = ThematicSeparator.none
    var usesSmartPunctuation = false
    var startsDocumentsOnNewPages = true
    var preservesHeadingStructure = true
    var theme: WordExportTheme?
}

nonisolated struct WordCompilationSource: Sendable {
    var title: String
    var markdown: String
    var sourceDirectory: URL?
    var language: String
    var sourceURL: URL? = nil
}

nonisolated enum WordCompilation {
    static let headingWarning = "Heading 6 remains Heading 6; it never becomes Heading 7. Heading 5 and Heading 6 can therefore both become Heading 6."

    static func document(sources: [WordCompilationSource], options: WordExportOptions) throws -> WordDocumentModel {
        var result = WordDocumentModel()
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            var document = try MarkdownToWordConverter.document(from: source.markdown, thematicSeparator: options.thematicSeparator, checkCancellation: { try Task.checkCancellation() })
            document = MarkdownToWordConverter.applyingTheme(options.theme, to: document)
            // Leading blank paragraphs are content, but do not obscure the title.
            let titleIndex = document.blocks.firstIndex { !isEmptyParagraph($0) } ?? document.blocks.count
            if titleIndex == document.blocks.count || !isTitle(document.blocks[titleIndex]) {
                document.blocks.insert(.paragraph(WordParagraph(runs: [WordRun(text: source.title)], headingLevel: 1)), at: titleIndex)
            }
            if index > 0, !options.startsDocumentsOnNewPages,
               result.blocks.last.map(isEmptyParagraph) != true,
               document.blocks.first.map(isEmptyParagraph) != true {
                result.blocks.append(.paragraph(WordParagraph(language: source.language)))
            }
            func transform(_ blocks: [WordBlock], topLevel: Bool) throws -> [WordBlock] {
                try blocks.enumerated().map { offset, block in
                    try Task.checkCancellation()
                    switch block {
                    case .paragraph(var paragraph):
                        // Only the first source can supply the compilation's opening pair.
                        // Heading shifting disables the pair because its H2 becomes H3.
                        if index > 0 || !options.preservesHeadingStructure { paragraph.openingStyle = nil }
                        if !options.preservesHeadingStructure, let level = paragraph.headingLevel,
                           !(index == 0 && topLevel && offset == titleIndex) {
                            paragraph.headingLevel = min(6, level + 1)
                        }
                        if var list = paragraph.list {
                            list.identifier = "source\(index)-\(list.identifier)"
                            paragraph.list = list
                        }
                        paragraph.sourceDirectory = source.sourceDirectory
                        paragraph.language = source.language
                        if topLevel && offset == 0 && index > 0 {
                            paragraph.pageBreakBefore = options.startsDocumentsOnNewPages
                        }
                        return .paragraph(paragraph)
                    case .table(var table):
                        for row in table.rows.indices {
                            table.rows[row].cells = try table.rows[row].cells.map { try transform($0, topLevel: false) }
                        }
                        return .table(table)
                    }
                }
            }
            if options.usesSmartPunctuation { document.blocks = try SmartPunctuation.wordBlocks(document.blocks) }
            result.blocks += try transform(document.blocks, topLevel: true)
        }
        return result
    }

    private static func isEmptyParagraph(_ block: WordBlock) -> Bool {
        guard case .paragraph(let paragraph) = block,
              paragraph.headingLevel == nil, paragraph.list == nil,
              !paragraph.isCodeBlock, !paragraph.isBlockQuote else { return false }
        return paragraph.runs.allSatisfy { $0.image == nil && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func isTitle(_ block: WordBlock) -> Bool {
        if case .paragraph(let paragraph) = block { return paragraph.headingLevel == 1 }
        return false
    }

    static func write(title: String, sources: [WordCompilationSource], options: WordExportOptions) throws -> Data {
        guard !sources.isEmpty else { throw WordThemeError.invalid("Select at least one document.") }
        return try WordprocessingMLWriter.write(
            title: title, document: document(sources: sources, options: options),
            documentLanguage: sources[0].language, theme: options.theme
        )
    }
}

/// Expands folders at their position in the saved order, without pin promotion.
enum CompilationSelection {
    static func documents(in directory: URL, documents: [Document], folders: [LibraryFolder], metadata: DocumentLibraryMetadataStore) -> [Document] {
        let parent = directory.standardizedFileURL
        let children = documents.filter { $0.url.deletingLastPathComponent().standardizedFileURL.path == parent.path }
        let subfolders = folders.filter { $0.url.deletingLastPathComponent().standardizedFileURL.path == parent.path }
        let byURL = Dictionary(uniqueKeysWithValues: children.map { ($0.url, $0) })
        return metadata.manuallyOrdered(children.map(\.url) + subfolders.map(\.url)).flatMap { url in
            if let document = byURL[url] { return [document] }
            return self.documents(in: url, documents: documents, folders: folders, metadata: metadata)
        }
    }

    static func appending(_ documents: [Document], to existing: [Document]) -> [Document] {
        var seen = Set(existing.map(\.url))
        return existing + documents.filter { seen.insert($0.url).inserted }
    }
}
