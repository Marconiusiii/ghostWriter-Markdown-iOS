import Foundation

nonisolated struct WordExportOptions: Equatable, Sendable {
    var startsDocumentsOnNewPages = true
    var preservesHeadingStructure = true
    var theme: WordExportTheme?
}

nonisolated struct WordCompilationSource: Sendable {
    var title: String
    var markdown: String
    var sourceDirectory: URL?
    var language: String
}

nonisolated enum WordCompilation {
    static let headingWarning = "Heading 6 remains Heading 6; it never becomes Heading 7. Heading 5 and Heading 6 can therefore both become Heading 6."

    static func document(sources: [WordCompilationSource], options: WordExportOptions) -> WordDocumentModel {
        var result = WordDocumentModel()
        for (index, source) in sources.enumerated() {
            var document = MarkdownToWordConverter.document(from: source.markdown)
            // Every source has a title paragraph, including empty documents.
            if document.blocks.isEmpty || !isTitle(document.blocks[0]) {
                document.blocks.insert(.paragraph(WordParagraph(runs: [WordRun(text: source.title)], headingLevel: 1)), at: 0)
            }
            func transform(_ blocks: [WordBlock], topLevel: Bool) -> [WordBlock] {
                blocks.enumerated().map { offset, block in
                    switch block {
                    case .paragraph(var paragraph):
                        if !options.preservesHeadingStructure, let level = paragraph.headingLevel,
                           !(index == 0 && topLevel && offset == 0) {
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
                            table.rows[row].cells = table.rows[row].cells.map { transform($0, topLevel: false) }
                        }
                        return .table(table)
                    }
                }
            }
            result.blocks += transform(document.blocks, topLevel: true)
        }
        return result
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
