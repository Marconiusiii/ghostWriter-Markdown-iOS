import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct FeedbackFeatureTests {
    @Test func exclusionDefaultsPersistAndFollowFolderLifecycle() throws {
        let suite = "Feedback-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = URL(fileURLWithPath: "/Library")
        let folder = root.appendingPathComponent("Book")
        let file = folder.appendingPathComponent("Notes.md")
        let metadata = DocumentLibraryMetadataStore(defaults: defaults)
        metadata.useLibraryRoot(root)
        #expect(metadata.isIncludedByDefault(file))
        metadata.toggleDefaultInclusion(for: file)
        metadata.toggleDefaultInclusion(for: folder)
        let restored = DocumentLibraryMetadataStore(defaults: defaults)
        restored.useLibraryRoot(root)
        #expect(!restored.isIncludedByDefault(file))
        #expect(restored.inclusionActionLabel(for: file) == "Always Include")
        let moved = root.appendingPathComponent("Draft")
        restored.migrateManualOrder(from: folder, to: moved)
        #expect(!restored.isIncludedByDefault(moved.appendingPathComponent("Notes.md")))
        #expect(restored.isIncludedByDefault(file))
        let deleted = root.appendingPathComponent(".RecentlyDeleted/Book")
        restored.migrateManualOrder(from: moved, to: deleted)
        restored.migrateManualOrder(from: deleted, to: moved)
        #expect(!restored.isIncludedByDefault(moved))
        restored.toggleDefaultInclusion(for: moved)
        #expect(restored.isIncludedByDefault(moved))
        #expect(!restored.isIncludedByDefault(moved.appendingPathComponent("Notes.md")))
        restored.removeFolderPreferences(at: moved)
        #expect(restored.isIncludedByDefault(moved.appendingPathComponent("Notes.md")))
    }

    @Test func folderCountsMatchSourceCharactersAndWhitespaceWords() throws {
        let texts = ["# Chapter\n\nHello, world!", "", "café 👩🏽‍💻\nnext\tword"]
        for text in texts {
            let result = try FolderTextCount.count(text)
            #expect(result.characters == text.count)
            #expect(result.words == text.split(whereSeparator: \.isWhitespace).count)
        }
    }

    @Test func stylesheetUsesCurrentRootAndReadsEditsWithoutCaching() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let absent = try await WordStylesheetLoader.load(in: root, enabled: true)
        #expect(absent == nil)
        let folder = WordStylesheetLoader.directory(in: root)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        let url = folder.appendingPathComponent(WordStylesheetLoader.filename)
        try Data(#"{"version":1,"body":{"font":"Georgia"}}"#.utf8).write(to: url)
        let first = try await WordStylesheetLoader.load(in: root, enabled: true)
        #expect(first != nil)
        let disabled = try await WordStylesheetLoader.load(in: root, enabled: false)
        #expect(disabled == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try Data("invalid JSON".utf8).write(to: url)
        do { _ = try await WordStylesheetLoader.load(in: root, enabled: true); Issue.record("Invalid stylesheet accepted") }
        catch { }
    }

    @Test func stylesheetFolderIsReservedOnlyAtStorageRoot() {
        let root = URL(fileURLWithPath: "/Library")
        #expect(WordStylesheetLoader.contains(root.appendingPathComponent("Word Stylesheets"), in: root))
        #expect(WordStylesheetLoader.contains(root.appendingPathComponent("Word Stylesheets/notes.md"), in: root))
        #expect(!WordStylesheetLoader.contains(root.appendingPathComponent("Book/Word Stylesheets/notes.md"), in: root))
        #expect(!WordStylesheetLoader.contains(root.appendingPathComponent("Word Stylesheets draft/notes.md"), in: root))
    }

    @Test func disabledStylesheetDoesNotCreateFolderOrUseLegacyRootFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disabled = try await WordStylesheetLoader.load(in: root, enabled: false)
        #expect(disabled == nil)
        #expect(!FileManager.default.fileExists(atPath: WordStylesheetLoader.directory(in: root).path))
        try Data(#"{"version":1}"#.utf8).write(to: root.appendingPathComponent(WordStylesheetLoader.filename))
        let enabled = try await WordStylesheetLoader.load(in: root, enabled: true)
        #expect(enabled == nil)
    }

    #if os(iOS)
    @Test func libraryScansExcludeStylesheetsAndTheirMarkdownContents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = WordStylesheetLoader.directory(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Hidden".utf8).write(to: folder.appendingPathComponent("Notes.md"))
        try Data("Visible".utf8).write(to: root.appendingPathComponent("Chapter.md"))
        let store = DocumentStore(directory: root)
        store.refresh()
        #expect(store.documents.map { $0.url.lastPathComponent } == ["Chapter.md"])
        #expect(!store.folders.contains { $0.url == folder })
    }
    #endif

    @Test func ellipsesPreserveProtectedTextAndLongerRuns() {
        let values: [ExportInline] = [.text("Wait... "), .strong([.text("Really...")]), .text(" .... … "), .code("..."), .link(destination: "https://example.org/...", content: [.text("More...")])]
        #expect(SmartPunctuation.inlines(values) == [.text("Wait… "), .strong([.text("Really…")]), .text(" .... … "), .code("..."), .link(destination: "https://example.org/...", content: [.text("More…")])])
        #expect(SmartPunctuation.convert([.init(text: "https://example.org/... ...")]) == ["https://example.org/... …"])
    }
}
