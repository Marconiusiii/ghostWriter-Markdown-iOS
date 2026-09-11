import Foundation

nonisolated enum CompilationFileWriter {
    static func write(title: String, sources: [WordCompilationSource], settings: CompilationExportSettings) async throws -> URL {
        guard !sources.isEmpty else { throw WordThemeError.invalid("Select at least one document.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ghostWriter-Compilation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try Task.checkCancellation()
            let safe = title.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-")
            let name = String(safe.prefix(120)).isEmpty ? "Compilation" : String(safe.prefix(120))
            let url = root.appendingPathComponent(name).appendingPathExtension(settings.format.fileExtension)
            let language = sources[0].language
            let data: Data
            var linkedAssets: [String] = []
            if settings.format == .word {
                var wordOptions = settings.word
                wordOptions.usesSmartPunctuation = settings.usesSmartPunctuation
                wordOptions.thematicSeparator = settings.thematicSeparator
                data = try WordCompilation.write(title: title, sources: sources, options: wordOptions)
            } else {
                let preserve = settings.format.supportsHeadingOptions ? settings.preservesHeadings : true
                let document = try CompilationDocument.prepare(sources: sources, preservesHeadings: preserve, assetDirectory: root, includesImages: ![.plainText, .brf].contains(settings.format), usesSmartPunctuation: settings.usesSmartPunctuation)
                linkedAssets = document.compilationLinkedAssets
                switch settings.format {
                case .word: throw WordThemeError.invalid("Invalid export format.")
                case .plainText:
                    data = Data(PlainTextWriter.write(title: title, markdown: "", preparedDocument: document, thematicSeparator: settings.thematicSeparator).utf8)
                case .markdown:
                    data = Data(CompilationMarkdownWriter.write(document).utf8)
                case .html:
                    data = Data(EPUBWriter.compilationHTML(title: title, document: document, sourceDirectory: root, language: language).utf8)
                case .pdf:
                    data = try TaggedPDFWriter.write(title: title, markdown: "", sourceDirectory: root, documentLanguage: language, preparedDocument: document, startsDocumentsOnNewPages: settings.startsOnNewPages)
                case .epub:
                    data = try EPUBWriter.write(title: title, markdown: "", sourceDirectory: root, documentLanguage: language, preparedDocument: document)
                case .powerPoint:
                    data = try await PowerPointWriter.writeLoadingImages(title: title, markdown: "", theme: settings.powerPointTheme, font: settings.powerPointFont, sourceDirectory: root, documentLanguage: language, preparedDocument: document)
                case .eBraille:
                    data = try await EBrailleWriter.write(title: title, markdown: "", metadata: settings.eBraille, translator: LiblouisBridge.shared, sourceDirectory: root, documentLanguage: language, preparedDocument: document)
                case .brf:
                    data = try await BRFWriter.write(markdown: "", title: title, grade: settings.brfGrade, pageSetup: .init(cellsPerLine: settings.brfCustomLayout ? settings.brfCells : 40, linesPerPage: settings.brfCustomLayout ? settings.brfLines : 25), outputPurpose: settings.brfPurpose, includeBraillePageNumbers: settings.brfPageNumbers, translator: LiblouisBridge.shared, documentLanguage: language, preparedDocument: document)
                }
            }
            try Task.checkCancellation()
            try data.write(to: url, options: .atomic)
            // Markdown carries relative assets; share a portable package when needed.
            let hasAssets = FileManager.default.fileExists(atPath: root.appendingPathComponent(".ghostwriter-assets-compilation").path)
            let needsAssetPackage = settings.format == .markdown ? hasAssets : (!linkedAssets.isEmpty && [.html, .pdf, .powerPoint, .plainText].contains(settings.format))
            if needsAssetPackage {
                var entries = [url.lastPathComponent: data]
                let files = FileManager.default.enumerator(at: root.appendingPathComponent(".ghostwriter-assets-compilation"), includingPropertiesForKeys: [.isRegularFileKey])
                while let file = files?.nextObject() as? URL {
                    try Task.checkCancellation()
                    if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                        entries[String(file.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: file)
                    }
                }
                let archive = root.appendingPathComponent(name).appendingPathExtension("zip")
                try WordPackage.create(entries: entries).write(to: archive, options: .atomic)
                try Task.checkCancellation()
                return archive
            }
            try Task.checkCancellation()
            return url
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}
