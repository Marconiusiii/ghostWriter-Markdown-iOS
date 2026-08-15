import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct WordImportTests {
    @Test func importsWordDocumentAsMarkdown() async throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriterWordLibrary-\(UUID().uuidString)", isDirectory: true)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("Word Import-\(UUID().uuidString)")
            .appendingPathExtension("docx")
        let store = DocumentStore(directory: library)
        defer {
            try? FileManager.default.removeItem(at: library)
            try? FileManager.default.removeItem(at: source)
        }
        let data = try MarkdownToWordConverter.convert(
            title: "Word Import",
            markdown: "# Imported\n\nA **formatted** document."
        )
        try data.write(to: source)

        let result = await store.importDocuments(from: [source])

        #expect(result.failedFileNames.isEmpty)
        let imported = try #require(result.imported.first)
        #expect(imported.url.pathExtension == "md")
        #expect(try store.text(for: imported).contains("# Imported"))
        #expect(try store.text(for: imported).contains("**formatted**"))
    }

    @Test func corruptWordImportDoesNotCreateMarkdownFile() async throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriterWordLibrary-\(UUID().uuidString)", isDirectory: true)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("Broken-\(UUID().uuidString)")
            .appendingPathExtension("docx")
        let store = DocumentStore(directory: library)
        defer {
            try? FileManager.default.removeItem(at: library)
            try? FileManager.default.removeItem(at: source)
        }
        try Data("not a Word package".utf8).write(to: source)

        let result = await store.importDocuments(from: [source])

        #expect(result.imported.isEmpty)
        #expect(result.failedFileNames == [source.lastPathComponent])
        #expect(store.documents.isEmpty)
        #expect(store.lastError?.contains("valid Word document") == true)
    }

    @Test func importsWordImagesIntoHiddenDocumentAssets() async throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriterWordImageLibrary-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriterWordImageSource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("Images.docx")
        let image = sourceDirectory.appendingPathComponent("sample.png")
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try png.write(to: image)
        let store = DocumentStore(directory: library)
        defer {
            try? FileManager.default.removeItem(at: library)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let data = try MarkdownToWordConverter.convert(
            title: "Images",
            markdown: "![Sample image](sample.png)",
            sourceDirectory: sourceDirectory
        )
        try data.write(to: source)

        let result = await store.importDocuments(from: [source])

        #expect(result.failedFileNames.isEmpty)
        #expect(result.notices.isEmpty)
        let imported = try #require(result.imported.first)
        let markdown = try store.text(for: imported)
        #expect(markdown.contains("![Sample image](.ghostwriter-assets-"))
        let directoryName = try #require(DocumentAssets.directoryNames(in: markdown).first)
        let assetDirectory = DocumentAssets.directory(named: directoryName, beside: imported.url)
        #expect(FileManager.default.fileExists(
            atPath: assetDirectory.appendingPathComponent("image1.png").path
        ))
    }
}
