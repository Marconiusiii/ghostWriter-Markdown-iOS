import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct CompilationOrderingTests {
    private func document(_ url: URL) -> Document { Document(url: url, created: .distantPast, modified: .distantPast, byteCount: 0) }

    @Test func savedMixedOrderExpandsFoldersAndIgnoresPinning() throws {
        let suite = "CompilationOrderingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let metadata = DocumentLibraryMetadataStore(defaults: defaults)
        let root = URL(fileURLWithPath: "/library")
        metadata.useLibraryRoot(root)
        let folder = LibraryFolder(url: root.appendingPathComponent("Folder"))
        let a = document(root.appendingPathComponent("A.md"))
        let b = document(root.appendingPathComponent("B.md"))
        let nested = document(folder.url.appendingPathComponent("Nested.md"))
        metadata.setManualOrder([b.url, folder.url, a.url], in: root)
        metadata.togglePin(for: a.url)
        let ordered = CompilationSelection.documents(in: root, documents: [a, nested, b], folders: [folder], metadata: metadata)
        #expect(ordered.map(\.url) == [b.url, nested.url, a.url])
        let tree = CompilationSelection.folder(at: root, documents: [a, nested, b], folders: [folder], metadata: metadata)
        #expect(tree.includedDocuments == ordered)
        #expect(tree.children.map(\.id) == [b.url, folder.url, a.url])
        #expect(tree.children[1].children.map(\.id) == [nested.url])
        #expect(tree.children.allSatisfy { $0.isIncluded })
        #expect(CompilationSelection.appending([a, nested, b], to: ordered) == ordered)
        let restored = DocumentLibraryMetadataStore(defaults: defaults)
        restored.useLibraryRoot(root)
        #expect(restored.manuallyOrdered([a.url, folder.url, b.url]) == [b.url, folder.url, a.url])
        #expect(DocumentSort(field: .manual).sorted([a, b], metadata: metadata).first?.url == a.url)
    }

    @Test func projectScopeContainsOnlyChildrenWithIndependentSelection() throws {
        let suite = "CompilationScopeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let metadata = DocumentLibraryMetadataStore(defaults: defaults)
        let root = URL(fileURLWithPath: "/library/Book")
        metadata.useLibraryRoot(root.deletingLastPathComponent())
        let folder = LibraryFolder(url: root.appendingPathComponent("Chapters"))
        let title = document(root.appendingPathComponent("title.md"))
        let chapter = document(folder.url.appendingPathComponent("chapter.md"))
        metadata.setManualOrder([title.url, folder.url], in: root)
        var items = CompilationSelection.items(in: root, documents: [chapter, title], folders: [folder], metadata: metadata)
        #expect(items.map(\.id) == [title.url, folder.url])
        #expect(!items.contains { $0.id == root })
        #expect(items.flatMap(\.includedDocuments) == [title, chapter])
        items[1].isIncluded = false
        #expect(items.flatMap(\.includedDocuments) == [title])
        items[1].isIncluded = true
        items.swapAt(0, 1)
        #expect(items.flatMap(\.includedDocuments) == [chapter, title])
    }

    @Test func sortPreferencesAreIndependentAndPersistThroughRenameAndMove() throws {
        let suite = "FolderSortTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = URL(fileURLWithPath: "/library")
        let folder = root.appendingPathComponent("Book")
        let nested = folder.appendingPathComponent("Chapters")
        let fallback = DocumentSort(field: .modified, direction: .descending)
        let rootSort = DocumentSort(field: .created, direction: .ascending)
        let folderSort = DocumentSort(field: .manual, direction: .descending)
        let nestedSort = DocumentSort(field: .name, direction: .descending)
        let metadata = DocumentLibraryMetadataStore(defaults: defaults)
        metadata.useLibraryRoot(root)
        #expect(metadata.sort(in: folder, fallback: fallback) == fallback)
        metadata.setSort(rootSort, in: root)
        metadata.setSort(folderSort, in: folder)
        metadata.setSort(nestedSort, in: nested)
        #expect(metadata.sort(in: root, fallback: fallback) == rootSort)
        #expect(metadata.sort(in: folder, fallback: fallback) == folderSort)
        #expect(metadata.sort(in: root.appendingPathComponent("Other"), fallback: fallback) == fallback)
        let restored = DocumentLibraryMetadataStore(defaults: defaults)
        restored.useLibraryRoot(root)
        #expect(restored.sort(in: root, fallback: fallback) == rootSort)
        #expect(restored.sort(in: folder, fallback: fallback) == folderSort)
        let renamed = root.appendingPathComponent("Renamed")
        restored.migrateManualOrder(from: folder, to: renamed)
        #expect(restored.sort(in: folder, fallback: fallback) == fallback)
        #expect(restored.sort(in: renamed, fallback: fallback) == folderSort)
        #expect(restored.sort(in: renamed.appendingPathComponent("Chapters"), fallback: fallback) == nestedSort)
        let moved = root.appendingPathComponent("Archive/Renamed")
        restored.migrateManualOrder(from: renamed, to: moved)
        #expect(restored.sort(in: moved, fallback: fallback) == folderSort)
        #expect(restored.sort(in: moved.appendingPathComponent("Chapters"), fallback: fallback) == nestedSort)
        #expect(restored.sort(in: root, fallback: fallback) == rootSort)
        let reopened = DocumentLibraryMetadataStore(defaults: defaults)
        reopened.useLibraryRoot(root)
        #expect(reopened.sort(in: moved.appendingPathComponent("Chapters"), fallback: fallback) == nestedSort)
    }

    @Test func folderInclusionRestoresDescendantChoicesAndMovesAsAUnit() {
        let root = URL(fileURLWithPath: "/library")
        let a = document(root.appendingPathComponent("Folder/A.md"))
        let b = document(root.appendingPathComponent("Folder/Nested/B.md"))
        let c = document(root.appendingPathComponent("C.md"))
        var folder = CompilationItem(item: .folder(LibraryFolder(url: root.appendingPathComponent("Folder"))), children: [
            CompilationItem(item: .document(a), isIncluded: false),
            CompilationItem(item: .folder(LibraryFolder(url: root.appendingPathComponent("Folder/Nested"))), children: [CompilationItem(item: .document(b))])
        ])
        #expect(folder.includedDocuments == [b])
        folder.isIncluded = false
        #expect(folder.includedDocuments.isEmpty)
        #expect(folder.children[1].isIncluded)
        folder.isIncluded = true
        #expect(folder.includedDocuments == [b])
        #expect(!folder.children[0].isIncluded)
        var tree = CompilationItem(item: .folder(LibraryFolder(url: root)), children: [folder, CompilationItem(item: .document(c))])
        #expect(tree.includedDocuments == [b, c])
        tree.children.swapAt(0, 1)
        #expect(tree.includedDocuments == [c, b])
        tree.children[1].children[1].isIncluded = false
        #expect(tree.includedDocuments == [c])
        tree.isIncluded = false
        #expect(tree.includedDocuments.isEmpty)
        tree.isIncluded = true
        #expect(tree.includedDocuments == [c])
    }

    @Test func renameMoveAndMissingItemsPreserveOrder() throws {
        let suite = "CompilationOrderingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let metadata = DocumentLibraryMetadataStore(defaults: defaults)
        let root = URL(fileURLWithPath: "/library")
        metadata.useLibraryRoot(root)
        let folder = root.appendingPathComponent("Folder")
        let moved = root.appendingPathComponent("Renamed")
        let a = folder.appendingPathComponent("A.md")
        let b = folder.appendingPathComponent("B.md")
        let c = root.appendingPathComponent("C.md")
        metadata.setManualOrder([folder, c], in: root)
        metadata.setManualOrder([b, a], in: folder)
        metadata.migrateManualOrder(from: folder, to: moved)
        #expect(metadata.manuallyOrdered([c, moved]) == [moved, c])
        let newA = moved.appendingPathComponent("A.md")
        let newB = moved.appendingPathComponent("B.md")
        #expect(metadata.manuallyOrdered([newA, newB]) == [newB, newA])
        // The Library also migrates document metadata after a folder rename.
        metadata.migrateMetadata(from: a, to: newA)
        metadata.migrateMetadata(from: b, to: newB)
        #expect(metadata.manualOrders["Renamed"] == ["Renamed/B.md", "Renamed/A.md"])

        metadata.migrateManualOrder(from: newB, to: root.appendingPathComponent("B.md"))
        #expect(metadata.manuallyOrdered([root.appendingPathComponent("B.md"), c, moved]) == [moved, c, root.appendingPathComponent("B.md")])
        #expect(metadata.manuallyOrdered([newA, moved.appendingPathComponent("New.md")]) == [newA, moved.appendingPathComponent("New.md")])
        #expect(metadata.manuallyOrdered([newA]) == [newA])
    }
}
