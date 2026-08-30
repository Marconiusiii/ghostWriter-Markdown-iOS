import Foundation

nonisolated enum PowerPointToMarkdownConverter {
    static func importDocument(
        data: Data,
        options: PowerPointImportOptions = PowerPointImportOptions(),
        assetDirectoryName: String
    ) throws -> MarkdownDocumentImport {
        // The caller supplies a new managed attachment directory, never a ZIP path.
        guard assetDirectoryName.hasPrefix(".ghostwriter-assets-"),
              !assetDirectoryName.contains("/"), !assetDirectoryName.contains("\\"),
              !assetDirectoryName.contains("..") else { throw PowerPointImportError.invalidPackage }
        let reader = try PowerPointDocumentReader(data: data, options: options, assetDirectory: assetDirectoryName)
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
