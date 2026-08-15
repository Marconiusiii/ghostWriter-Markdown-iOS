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
}
