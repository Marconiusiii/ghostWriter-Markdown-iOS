//
//  DocumentStoreTests.swift
//  ghostWriterTests
//
//  These exist because autosave shipped a bug that created a new file on every
//  save instead of overwriting one. That is the kind of failure that quietly
//  destroys someone's work, so the save path is pinned down here.
//

import Foundation
import Testing
@testable import ghostWriter

@MainActor
struct DocumentStoreTests {

    /// Each test gets its own throwaway directory.
    private func makeStore() -> DocumentStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriterTests-\(UUID().uuidString)", isDirectory: true)
        return DocumentStore(directory: directory)
    }

    private func cleanUp(_ store: DocumentStore) {
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test func repeatedSavesOverwriteOneFile() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Note", contents: "first") else {
            Issue.record("Could not create the document")
            return
        }

        // Simulate autosave firing many times, as it would while typing.
        for pass in 2...20 {
            #expect(store.save(text: "pass \(pass)", to: url))
        }

        store.refresh()
        #expect(store.documents.count == 1, "Autosave must never create extra files")
        #expect(try store.text(for: store.documents[0]) == "pass 20")
    }

    @Test func guardedSaveWritesWhenTheFileIsUnchanged() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Note", contents: "first") else {
            Issue.record("Could not create the document")
            return
        }

        let result = store.save(
            text: "second",
            to: url,
            ifUnchangedFrom: "first"
        )

        #expect(result == .saved)
        #expect(try String(contentsOf: url, encoding: .utf8) == "second")
    }

    @Test func guardedSaveDoesNotOverwriteAnExternalChange() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Note", contents: "original") else {
            Issue.record("Could not create the document")
            return
        }
        try "changed in Files".write(to: url, atomically: true, encoding: .utf8)

        let result = store.save(
            text: "changed in ghostWriter",
            to: url,
            ifUnchangedFrom: "original"
        )

        #expect(result == .changedOnDisk("changed in Files"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "changed in Files")
    }

    @Test func guardedSaveDoesNotRecreateAnExternallyDeletedFile() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Note", contents: "original") else {
            Issue.record("Could not create the document")
            return
        }
        try FileManager.default.removeItem(at: url)

        let result = store.save(
            text: "changed in ghostWriter",
            to: url,
            ifUnchangedFrom: "original"
        )

        #expect(result == .missing)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func conflictCopyPreservesBothVersions() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let originalURL = store.createDocument(
            named: "Note",
            contents: "original"
        ) else {
            Issue.record("Could not create the document")
            return
        }
        try "external version".write(
            to: originalURL,
            atomically: true,
            encoding: .utf8
        )

        let result = store.save(
            text: "editor version",
            to: originalURL,
            ifUnchangedFrom: "original"
        )
        let copyURL = store.createDocument(
            named: "Note copy",
            contents: "editor version"
        )

        #expect(result == .changedOnDisk("external version"))
        #expect(copyURL != nil)
        #expect(try String(contentsOf: originalURL, encoding: .utf8) == "external version")
        if let copyURL {
            #expect(try String(contentsOf: copyURL, encoding: .utf8) == "editor version")
        }
    }

    @Test func savingDoesNotRepublishTheDocumentList() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Note", contents: "body") else {
            Issue.record("Could not create the document")
            return
        }
        store.refresh()
        let before = store.documents

        store.save(text: "changed", to: url)

        // The published array must be untouched by a save. Republishing it on
        // every keystroke is what caused the editor to lose its file handle and
        // create duplicates.
        #expect(store.documents == before)
    }

    @Test func createAvoidsNameCollisions() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        let first = store.createDocument(named: "Note", contents: "one")
        let second = store.createDocument(named: "Note", contents: "two")

        #expect(first != nil)
        #expect(second != nil)
        #expect(first != second, "A second document with the same name needs its own file")

        store.refresh()
        #expect(store.documents.count == 2)
    }

    @Test func renameMovesTheSameFile() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Before", contents: "body") else {
            Issue.record("Could not create the document")
            return
        }

        let renamed = store.rename(at: url, to: "After")
        #expect(renamed != nil)
        #expect(renamed?.deletingPathExtension().lastPathComponent == "After")

        store.refresh()
        #expect(store.documents.count == 1, "Rename must move the file, not copy it")
        #expect(try store.text(for: store.documents[0]) == "body")
    }

    @Test func renameToSameNameIsANoOp() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Note", contents: "body") else {
            Issue.record("Could not create the document")
            return
        }

        let result = store.rename(at: url, to: "Note")
        #expect(result == url)

        store.refresh()
        #expect(store.documents.count == 1)
    }

    @Test func sanitizeStripsPathCharacters() {
        // A title is derived from user text, so it must never be able to escape
        // the folder or produce an unwritable path.
        #expect(!DocumentStore.sanitize("../../etc/passwd").contains("/"))
        #expect(DocumentStore.sanitize("   ") == "Untitled")
        #expect(DocumentStore.sanitize("Perfectly Fine") == "Perfectly Fine")
    }

    @Test func invalidUTF8IsNotPresentedAsAnEmptyDocument() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = store.createDocument(named: "Encoded elsewhere") else {
            Issue.record("Could not create the document")
            return
        }
        let original = Data([0xff, 0xfe, 0xfd])
        try original.write(to: url)
        store.refresh()

        guard let document = store.documents.first else {
            Issue.record("The invalid UTF-8 file should still appear in the library")
            return
        }

        do {
            _ = try store.text(for: document)
            Issue.record("Invalid UTF-8 must produce a loading error")
        } catch {
            #expect(store.lastError?.contains("original file was not changed") == true)
        }

        #expect(try Data(contentsOf: url) == original)
    }
}
