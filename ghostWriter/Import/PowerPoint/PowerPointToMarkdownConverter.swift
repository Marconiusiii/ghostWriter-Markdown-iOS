import Foundation

nonisolated enum PowerPointToMarkdownConverter {
    /// The caller must keep file coordination and security-scoped access alive
    /// for this entire synchronous conversion, normally on a background task.
    static func importDocument(
        fileURL: URL,
        options: PowerPointImportOptions = PowerPointImportOptions(),
        assetDirectoryName: String
    ) throws -> MarkdownDocumentImport {
        try importDocument(package: PowerPointImportPackage(url: fileURL), options: options,
                           assetDirectoryName: assetDirectoryName)
    }

    static func importDocument(
        data: Data,
        options: PowerPointImportOptions = PowerPointImportOptions(),
        assetDirectoryName: String
    ) throws -> MarkdownDocumentImport {
        try importDocument(package: PowerPointImportPackage(data: data), options: options,
                           assetDirectoryName: assetDirectoryName)
    }

    private static func importDocument(
        package: PowerPointImportPackage,
        options: PowerPointImportOptions,
        assetDirectoryName: String
    ) throws -> MarkdownDocumentImport {
        // The caller supplies a new managed attachment directory, never a ZIP path.
        guard assetDirectoryName.hasPrefix(".ghostwriter-assets-"),
              !assetDirectoryName.contains("/"), !assetDirectoryName.contains("\\"),
              !assetDirectoryName.contains("..") else { throw PowerPointImportError.invalidPackage }
        let reader = PowerPointDocumentReader(package: package, options: options, assetDirectory: assetDirectoryName)
        let presentation = try reader.read()
        var sections: [String] = []
        for slide in presentation.slides {
            let title = WordBlock.paragraph(WordParagraph(runs: slide.title, headingLevel: slide.isTitleSlide ? 1 : 2))
            sections.append(WordToMarkdownConverter.markdown(from: WordDocumentModel(blocks: [title] + slide.blocks)))
            if !slide.notes.isEmpty {
                sections.append("***")
                sections.append(WordToMarkdownConverter.markdown(from: WordDocumentModel(blocks: slide.notes)))
            }
        }
        return MarkdownDocumentImport(
            markdown: sections.joined(separator: "\n\n") + "\n",
            assets: presentation.assets,
            imagesNeedingAlternativeText: presentation.imagesNeedingAlternativeText,
            assetDirectoryName: presentation.assets.isEmpty ? nil : assetDirectoryName,
            notices: presentation.notices
        )
    }
}
