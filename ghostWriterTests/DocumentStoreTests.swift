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

    @Test func asynchronousDocumentReadReturnsCompleteContents() async throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let contents = String(
            repeating: "Library opening stays responsive. ",
            count: 200
        )
        let url = try #require(
            store.createDocument(named: "Responsive", contents: contents)
        )
        let document = try #require(Document(fileURL: url))

        let loaded = try await store.textAsynchronously(for: document)

        #expect(loaded == contents)
    }

    @Test func asynchronousDocumentReadPreservesFailureReporting() async throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let missingURL = store.directory.appendingPathComponent("Missing.md")
        let document = Document(
            url: missingURL,
            created: .now,
            modified: .now,
            byteCount: 0
        )

        await #expect(throws: (any Error).self) {
            _ = try await store.textAsynchronously(for: document)
        }
        #expect(store.lastError?.contains("Could not open Missing") == true)
    }

    @Test func asynchronousRefreshPublishesACompleteFilesystemSnapshot() async throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let nested = store.directory
            .appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        try "background scan".write(
            to: nested.appendingPathComponent("Draft.md"),
            atomically: true,
            encoding: .utf8
        )

        await store.refreshAsynchronously()

        #expect(store.documents.map(\.displayName) == ["Draft"])
        #expect(store.folders.map(\.displayName) == ["Projects"])
    }

    @Test func nestedFoldersContainOnlyTheirDirectItems() async throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let projects = store.createFolder(
            named: "Projects",
            in: store.directory
        ), let archive = store.createFolder(
            named: "Archive",
            in: projects.url
        ) else {
            Issue.record("Could not create nested folders")
            return
        }
        _ = await store.createDocument(named: "Root", contents: "root")
        _ = await store.createDocument(named: "Project", contents: "project", in: projects.url)
        _ = await store.createDocument(named: "Archived", contents: "archive", in: archive.url)
        store.refresh()

        #expect(store.documents.count == 3)
        #expect(store.folders.count == 2)
        #expect(store.documents(directlyIn: store.directory).map(\.displayName) == ["Root"])
        #expect(store.documents(directlyIn: projects.url).map(\.displayName) == ["Project"])
        #expect(store.folders(directlyIn: projects.url).map(\.displayName) == ["Archive"])
    }

    @Test func deletedFolderRestoresToItsOriginalParent() async throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let parent = store.createFolder(named: "Parent", in: store.directory),
              let child = store.createFolder(named: "Child", in: parent.url) else {
            Issue.record("Could not create folders")
            return
        }
        _ = await store.createDocument(named: "Note", contents: "kept", in: child.url)

        guard let deletedURL = store.moveToRecentlyDeleted(child),
              let deletedFolder = store.recentlyDeletedFolders.first(where: {
                  $0.url == deletedURL
              }),
              let restoredURL = store.restore(deletedFolder) else {
            Issue.record("Could not delete and restore the folder")
            return
        }

        #expect(restoredURL.deletingLastPathComponent() == parent.url)
        #expect(FileManager.default.fileExists(
            atPath: restoredURL.appendingPathComponent("Note.md").path
        ))
    }

    @Test func folderCannotMoveInsideItself() {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let parent = store.createFolder(named: "Parent", in: store.directory),
              let child = store.createFolder(named: "Child", in: parent.url) else {
            Issue.record("Could not create folders")
            return
        }

        #expect(store.move(.folder(parent), to: child.url) == nil)
        #expect(FileManager.default.fileExists(atPath: parent.url.path))
    }

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

    @Test func asynchronousGuardedSaveWritesWhenTheFileIsUnchanged() async throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = await store.createDocument(named: "Note", contents: "first") else {
            Issue.record("Could not create the document")
            return
        }

        let result = await store.saveAsynchronously(
            text: "second",
            to: url,
            ifUnchangedFrom: "first"
        )

        #expect(result == .saved)
        #expect(try String(contentsOf: url, encoding: .utf8) == "second")
    }

    @Test func asynchronousGuardedSavePreservesAnExternalChange() async throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = await store.createDocument(named: "Note", contents: "original") else {
            Issue.record("Could not create the document")
            return
        }
        try "changed in Files".write(to: url, atomically: true, encoding: .utf8)

        let result = await store.saveAsynchronously(
            text: "changed in ghostWriter",
            to: url,
            ifUnchangedFrom: "original"
        )

        #expect(result == .changedOnDisk("changed in Files"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "changed in Files")
    }

    @Test func asynchronousDiskStateReportsDeletion() async throws {
        let store = makeStore()
        defer { cleanUp(store) }

        guard let url = await store.createDocument(named: "Note", contents: "original") else {
            Issue.record("Could not create the document")
            return
        }
        try FileManager.default.removeItem(at: url)

        let state = await store.diskStateAsynchronously(
            for: url,
            expectedContents: "original"
        )

        #expect(state == .missing)
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

    @Test func unavailableStorageCannotCreateOrSaveDocuments() {
        let store = makeStore()
        defer { cleanUp(store) }
        store.useDirectory(nil)

        #expect(store.createDocument(named: "Blocked") == nil)
        #expect(
            !store.save(
                text: "Blocked",
                to: store.directory.appendingPathComponent("Blocked.md")
            )
        )
        #expect(store.documents.isEmpty)
    }

    @Test func changingDirectoryShowsOnlyTheSelectedLibrary() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        _ = store.createDocument(named: "Local", contents: "Local body")
        store.refresh()
        #expect(store.documents.map(\.displayName) == ["Local"])

        let cloudDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterCloudTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: cloudDirectory) }
        store.useDirectory(cloudDirectory)
        _ = store.createDocument(named: "Cloud", contents: "Cloud body")
        store.refresh()

        #expect(store.documents.map(\.displayName) == ["Cloud"])
    }

    @Test func remoteOnlyDocumentRemainsVisibleWithoutBeingRead() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterRemoteTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = DocumentStore(directory: directory)
        defer { cleanUp(store) }
        let remoteURL = directory.appendingPathComponent("Remote.md")

        store.applyICloudSnapshot([
            ICloudDocumentSnapshot(
                url: remoteURL,
                created: Date(timeIntervalSince1970: 100),
                modified: Date(timeIntervalSince1970: 200),
                byteCount: 42,
                availability: .waitingForICloud,
                isRecentlyDeleted: false
            )
        ])

        #expect(store.documents.count == 1)
        #expect(store.documents[0].displayName == "Remote")
        #expect(store.documents[0].availability == .waitingForICloud)
        #expect(throws: Error.self) {
            try store.text(for: store.documents[0], reportFailure: false)
        }
    }

    @Test func requestingRemoteDocumentConfirmsReadableContents() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterDownloadTests-\(UUID().uuidString)",
                isDirectory: true
            )
        var requestedURL: URL?
        let store = DocumentStore(
            directory: directory,
            startDownloadingUbiquitousItem: {
                requestedURL = $0
                try "Downloaded".write(
                    to: $0,
                    atomically: true,
                    encoding: .utf8
                )
            }
        )
        defer { cleanUp(store) }
        let remoteURL = directory.appendingPathComponent("Remote.md")
        store.applyICloudSnapshot([
            ICloudDocumentSnapshot(
                url: remoteURL,
                created: .distantPast,
                modified: .distantPast,
                byteCount: 0,
                availability: .waitingForICloud,
                isRecentlyDeleted: false
            )
        ])

        #expect(await store.requestDownload(for: store.documents[0]))
        #expect(requestedURL == remoteURL)
        #expect(store.documents[0].availability == .available)
    }

    @Test func failedDownloadCanBeRequestedAgain() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterRetryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        var attempts = 0
        let store = DocumentStore(
            directory: directory,
            startDownloadingUbiquitousItem: { _ in
                attempts += 1
                if attempts == 1 {
                    throw CocoaError(.fileReadNoSuchFile)
                }
            }
        )
        defer { cleanUp(store) }
        let remoteURL = directory.appendingPathComponent("Remote.md")
        store.applyICloudSnapshot([
            ICloudDocumentSnapshot(
                url: remoteURL,
                created: .distantPast,
                modified: .distantPast,
                byteCount: 0,
                availability: .waitingForICloud,
                isRecentlyDeleted: false
            )
        ])

        #expect(!(await store.requestDownload(for: store.documents[0])))
        #expect(
            store.documents[0].availability.statusDescription
                == "Download failed"
        )
        store.lastError = nil
        #expect(await store.requestDownload(for: store.documents[0]))
        #expect(attempts == 2)
    }

    @Test func localDocumentDoesNotRequestICloudDownload() async {
        var requestCount = 0
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterLocalDownloadTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = DocumentStore(
            directory: directory,
            startDownloadingUbiquitousItem: { _ in requestCount += 1 }
        )
        defer { cleanUp(store) }
        _ = await store.createDocument(named: "Local", contents: "Body")
        store.refresh()

        #expect(await store.requestDownload(for: store.documents[0]))
        #expect(requestCount == 0)
    }

    @Test func syncRequestsCurrentICloudContentsForAvailableDocument() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterExplicitSyncTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("Current.md")
        try "Local version".write(to: url, atomically: true, encoding: .utf8)
        var requestCount = 0
        let store = DocumentStore(
            directory: directory,
            usesICloudStorage: true,
            startDownloadingUbiquitousItem: { requestedURL in
                requestCount += 1
                try "iCloud version".write(
                    to: requestedURL,
                    atomically: true,
                    encoding: .utf8
                )
            }
        )
        defer { cleanUp(store) }
        store.refresh()
        let document = try #require(store.documents.first)
        #expect(document.availability == .available)

        #expect(await store.synchronizeWithICloud(document))
        #expect(requestCount == 1)
        #expect(try String(contentsOf: url, encoding: .utf8) == "iCloud version")
        #expect(store.documents.first?.availability == .available)
    }

    @Test func failedExplicitSyncReportsTheDocumentName() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterExplicitSyncFailure-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("Current.md")
        try "Local version".write(to: url, atomically: true, encoding: .utf8)
        let store = DocumentStore(
            directory: directory,
            usesICloudStorage: true,
            startDownloadingUbiquitousItem: { _ in
                throw CocoaError(.fileReadUnknown)
            }
        )
        defer { cleanUp(store) }
        store.refresh()
        let document = try #require(store.documents.first)

        #expect(!(await store.synchronizeWithICloud(document)))
        #expect(store.documents.first?.availability.statusDescription == "Download failed")
        #expect(store.lastError?.contains("Could not sync Current with iCloud.") == true)
    }

    @Test func localStorageDoesNotOfferAnICloudSynchronizationRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterExplicitLocalSync-\(UUID().uuidString)",
                isDirectory: true
            )
        var requestCount = 0
        let store = DocumentStore(
            directory: directory,
            startDownloadingUbiquitousItem: { _ in requestCount += 1 }
        )
        defer { cleanUp(store) }
        _ = await store.createDocument(named: "Local", contents: "Body")
        store.refresh()
        let document = try #require(store.documents.first)

        #expect(!(await store.synchronizeWithICloud(document)))
        #expect(requestCount == 0)
    }

    @Test func staleWaitingSnapshotDoesNotDowngradeConfirmedDownload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterConfirmedDownload-\(UUID().uuidString)",
                isDirectory: true
            )
        let remoteURL = directory.appendingPathComponent("Remote.md")
        let modified = Date(timeIntervalSince1970: 200)
        let store = DocumentStore(
            directory: directory,
            startDownloadingUbiquitousItem: { url in
                try "Downloaded".write(
                    to: url,
                    atomically: true,
                    encoding: .utf8
                )
            }
        )
        defer { cleanUp(store) }
        let staleSnapshot = ICloudDocumentSnapshot(
            url: remoteURL,
            created: Date(timeIntervalSince1970: 100),
            modified: modified,
            byteCount: 10,
            availability: .waitingForICloud,
            isRecentlyDeleted: false
        )
        store.applyICloudSnapshot([staleSnapshot])

        #expect(await store.requestDownload(for: store.documents[0]))
        store.applyICloudSnapshot([staleSnapshot])

        #expect(store.documents[0].availability == .available)
        #expect(try store.text(for: store.documents[0]) == "Downloaded")
    }

    @Test func newerRemoteVersionCanReplaceConfirmedAvailability() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterNewerRemote-\(UUID().uuidString)",
                isDirectory: true
            )
        let remoteURL = directory.appendingPathComponent("Remote.md")
        let store = DocumentStore(
            directory: directory,
            startDownloadingUbiquitousItem: { url in
                try "Downloaded".write(
                    to: url,
                    atomically: true,
                    encoding: .utf8
                )
            }
        )
        defer { cleanUp(store) }
        store.applyICloudSnapshot([
            ICloudDocumentSnapshot(
                url: remoteURL,
                created: .distantPast,
                modified: Date(timeIntervalSince1970: 200),
                byteCount: 10,
                availability: .waitingForICloud,
                isRecentlyDeleted: false
            )
        ])
        #expect(await store.requestDownload(for: store.documents[0]))

        store.applyICloudSnapshot([
            ICloudDocumentSnapshot(
                url: remoteURL,
                created: .distantPast,
                modified: .distantFuture,
                byteCount: 20,
                availability: .waitingForICloud,
                isRecentlyDeleted: false
            )
        ])

        #expect(store.documents[0].availability == .waitingForICloud)
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

    @Test func iCloudCreationPlacesACompleteStagedDocument() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterCloudCreate-\(UUID().uuidString)",
                isDirectory: true
            )
        var placedData: Data?
        var placedURL: URL?
        let store = DocumentStore(
            directory: directory,
            usesICloudStorage: true,
            placeUbiquitousItem: { data, destination in
                placedData = data
                placedURL = destination
                try data.write(to: destination, options: .atomic)
            }
        )
        defer { cleanUp(store) }

        let createdURL = await store.createDocument(
            named: "Cloud Note",
            contents: "Complete contents"
        )

        #expect(createdURL == placedURL)
        #expect(placedData == Data("Complete contents".utf8))
        #expect(
            try String(contentsOf: #require(createdURL), encoding: .utf8)
                == "Complete contents"
        )
    }

    @Test func failedICloudPlacementDoesNotCreateACloudDocument() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterCloudFailure-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = DocumentStore(
            directory: directory,
            usesICloudStorage: true,
            placeUbiquitousItem: { _, _ in
                throw CocoaError(.fileWriteUnknown)
            }
        )
        defer { cleanUp(store) }

        let createdURL = await store.createDocument(
            named: "Failed",
            contents: "Do not lose this silently"
        )

        #expect(createdURL == nil)
        #expect(store.documents.isEmpty)
        #expect(store.lastError?.contains("in iCloud") == true)
    }

    @Test func iCloudDuplicateUsesStagedPlacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterCloudDuplicate-\(UUID().uuidString)",
                isDirectory: true
            )
        var placementCount = 0
        let store = DocumentStore(
            directory: directory,
            placeUbiquitousItem: { data, destination in
                placementCount += 1
                try data.write(to: destination, options: .atomic)
            }
        )
        defer { cleanUp(store) }
        _ = await store.createDocument(
            named: "Original",
            contents: "Body"
        )
        store.refresh()
        store.useDirectory(directory, usesICloudStorage: true)

        let duplicate = await store.duplicate(
            try #require(store.documents.first)
        )

        #expect(placementCount == 1)
        #expect(duplicate?.displayName == "Original copy")
        if let duplicate {
            #expect(try store.text(for: duplicate) == "Body")
        }
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

    @Test func deleteMovesDocumentToRecentlyDeleted() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        _ = store.createDocument(named: "Recoverable", contents: "Keep this")
        store.refresh()

        guard let document = store.documents.first else {
            Issue.record("Could not create the document")
            return
        }

        let deletedURL = store.moveToRecentlyDeleted(document)

        #expect(deletedURL != nil)
        #expect(store.documents.isEmpty)
        #expect(store.recentlyDeletedDocuments.count == 1)
        #expect(
            try store.text(for: store.recentlyDeletedDocuments[0])
                == "Keep this"
        )
    }

    @Test func restoreReturnsDocumentToLibrary() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        _ = store.createDocument(named: "Return", contents: "Restored text")
        store.refresh()

        guard let document = store.documents.first,
              store.moveToRecentlyDeleted(document) != nil,
              let deleted = store.recentlyDeletedDocuments.first else {
            Issue.record("Could not move the document to Recently Deleted")
            return
        }

        let restoredURL = store.restore(deleted)

        #expect(restoredURL != nil)
        #expect(store.recentlyDeletedDocuments.isEmpty)
        #expect(store.documents.count == 1)
        #expect(try store.text(for: store.documents[0]) == "Restored text")
    }

    @Test func staleICloudSnapshotDoesNotRecreateRestoredDeletion() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        _ = store.createDocument(named: "Return", contents: "Restored text")
        store.refresh()

        guard let original = store.documents.first,
              store.moveToRecentlyDeleted(original) != nil,
              let deleted = store.recentlyDeletedDocuments.first else {
            Issue.record("Could not prepare Recently Deleted")
            return
        }
        let staleDeletedSnapshot = ICloudDocumentSnapshot(
            url: deleted.url,
            created: deleted.created,
            modified: deleted.modified,
            byteCount: deleted.byteCount,
            availability: .available,
            isRecentlyDeleted: true
        )
        store.applyICloudSnapshot([staleDeletedSnapshot])

        #expect(store.restore(deleted) != nil)
        store.applyICloudSnapshot([staleDeletedSnapshot])

        #expect(store.recentlyDeletedDocuments.isEmpty)
        #expect(store.documents.map(\.displayName) == ["Return"])
    }

    @Test func restoreAvoidsNameCollisions() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        _ = store.createDocument(named: "Note", contents: "deleted version")
        store.refresh()

        guard let original = store.documents.first,
              store.moveToRecentlyDeleted(original) != nil,
              let deleted = store.recentlyDeletedDocuments.first else {
            Issue.record("Could not prepare Recently Deleted")
            return
        }

        _ = store.createDocument(named: "Note", contents: "current version")
        store.refresh()
        let restoredURL = store.restore(deleted)

        #expect(
            restoredURL?.deletingPathExtension().lastPathComponent == "Note 2"
        )
        #expect(store.documents.count == 2)
    }

    @Test func recentlyDeletedPreservesOriginalExtension() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let textFile = store.directory.appendingPathComponent("Plain.txt")
        try "plain text".write(
            to: textFile,
            atomically: true,
            encoding: .utf8
        )
        store.refresh()

        guard let document = store.documents.first,
              store.moveToRecentlyDeleted(document) != nil,
              let deleted = store.recentlyDeletedDocuments.first else {
            Issue.record("Could not prepare the text document")
            return
        }

        #expect(deleted.url.pathExtension == "txt")
        let restoredURL = store.restore(deleted)
        #expect(restoredURL?.pathExtension == "txt")
    }

    @Test func permanentDeletionRemovesTheFile() {
        let store = makeStore()
        defer { cleanUp(store) }
        _ = store.createDocument(named: "Disposable", contents: "body")
        store.refresh()

        guard let document = store.documents.first,
              store.moveToRecentlyDeleted(document) != nil,
              let deleted = store.recentlyDeletedDocuments.first else {
            Issue.record("Could not prepare Recently Deleted")
            return
        }

        #expect(store.deletePermanently(deleted))
        #expect(store.recentlyDeletedDocuments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: deleted.url.path))
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

    @Test func importCopiesUTF8MarkdownIntoTheLibrary() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriterImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let source = sourceDirectory.appendingPathComponent("Imported.markdown")
        try "# Imported\nBody".write(to: source, atomically: true, encoding: .utf8)

        let result = store.importDocuments(from: [source])

        #expect(result.failedFileNames.isEmpty)
        #expect(result.imported.count == 1)
        #expect(result.imported.first?.displayName == "Imported")
        if let imported = result.imported.first {
            #expect(try store.text(for: imported) == "# Imported\nBody")
        }
    }

    @Test func iCloudImportUsesStagedPlacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriterCloudImport-\(UUID().uuidString)",
                isDirectory: true
            )
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Cloud Import-\(UUID().uuidString).md"
            )
        try "Imported through staging".write(
            to: source,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: source) }
        var placementCount = 0
        let store = DocumentStore(
            directory: directory,
            usesICloudStorage: true,
            placeUbiquitousItem: { data, destination in
                placementCount += 1
                try data.write(to: destination, options: .atomic)
            }
        )
        defer { cleanUp(store) }

        let result = await store.importDocuments(from: [source])

        #expect(placementCount == 1)
        #expect(result.failedFileNames.isEmpty)
        #expect(result.imported.count == 1)
        #expect(
            try store.text(for: #require(result.imported.first))
                == "Imported through staging"
        )
    }

    @Test func importAvoidsNameCollisions() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        _ = store.createDocument(named: "Note", contents: "existing")
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriterImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let source = sourceDirectory.appendingPathComponent("Note.txt")
        try "imported".write(to: source, atomically: true, encoding: .utf8)

        let result = store.importDocuments(from: [source])

        #expect(result.imported.first?.displayName == "Note 2")
        store.refresh()
        #expect(store.documents.count == 2)
    }

    @Test func importRejectsInvalidUTF8WithoutCreatingAnEmptyFile() throws {
        let store = makeStore()
        defer { cleanUp(store) }
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("Unreadable-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data([0xff, 0xfe, 0xfd]).write(to: source)

        let result = store.importDocuments(from: [source])

        #expect(result.imported.isEmpty)
        #expect(result.failedFileNames == [source.lastPathComponent])
        #expect(store.documents.isEmpty)
        #expect(store.lastError?.contains("UTF-8") == true)
    }
}
