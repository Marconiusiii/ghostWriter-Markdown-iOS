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
        #expect(CompilationSelection.appending([a, nested, b], to: ordered) == ordered)
        let restored = DocumentLibraryMetadataStore(defaults: defaults)
        restored.useLibraryRoot(root)
        #expect(restored.manuallyOrdered([a.url, folder.url, b.url]) == [b.url, folder.url, a.url])
        #expect(DocumentSort(field: .manual).sorted([a, b], metadata: metadata).first?.url == a.url)
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
