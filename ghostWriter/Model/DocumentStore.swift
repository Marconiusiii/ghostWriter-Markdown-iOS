//
//  DocumentStore.swift
//  ghostWriter
//
//  Owns the ghostWriter folder inside the app's Documents directory. That
//  folder is exposed to the Files app, so the filesystem is the single source
//  of truth: the user can rename, delete, or add files outside the app and we
//  simply re-read rather than trying to keep a parallel database in sync.
//

import Foundation
import Observation

enum DocumentDiskState: Equatable {
    case unchanged
    case changed(String)
    case missing
    case unreadable
}

enum GuardedSaveResult: Equatable {
    case saved
    case changedOnDisk(String)
    case missing
    case failed
}

struct DocumentImportResult: Equatable {
    let imported: [Document]
    let failedFileNames: [String]
}

@Observable
final class DocumentStore {
    private(set) var documents: [Document] = []
    private(set) var recentlyDeletedDocuments: [Document] = []
    private(set) var storageAvailable: Bool
    /// Set when a filesystem operation fails so the UI can surface it rather
    /// than failing silently. Cleared once the user dismisses it.
    var lastError: String?

    private let fileAccess: CoordinatedFileAccess
    private let downloadUbiquitousItem: (URL) async throws -> Void
    private var iCloudSnapshotsByURL: [URL: ICloudDocumentSnapshot] = [:]
    private var activeDownloadURLs: Set<URL> = []
    private var confirmedAvailableVersions: [URL: Date] = [:]
    private var suppressedSnapshotURLs: Set<URL> = []

    /// The user-visible folder. Created on first access; creation failures are
    /// exposed through `lastError` rather than silently changing storage paths.
    private(set) var directory: URL
    private(set) var recentlyDeletedDirectory: URL

    init(
        directory: URL? = nil,
        storageAvailable: Bool = true,
        fileAccess: CoordinatedFileAccess = CoordinatedFileAccess(),
        startDownloadingUbiquitousItem:
            @escaping (URL) async throws -> Void = {
                try await CoordinatedFileAccess
                    .downloadAndVerifyUbiquitousItem(at: $0)
        }
    ) {
        self.storageAvailable = storageAvailable
        self.fileAccess = fileAccess
        self.downloadUbiquitousItem =
            startDownloadingUbiquitousItem
        let resolvedDirectory: URL
        if let directory {
            resolvedDirectory = directory
        } else {
            let documentsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            resolvedDirectory = documentsRoot.appendingPathComponent(
                "ghostWriter",
                isDirectory: true
            )
        }
        self.directory = resolvedDirectory
        self.recentlyDeletedDirectory = resolvedDirectory
            .appendingPathComponent("Recently Deleted", isDirectory: true)
        if storageAvailable {
            createDirectoryIfNeeded()
        }
    }

    func useDirectory(_ directory: URL?) {
        guard let directory else {
            storageAvailable = false
            documents = []
            recentlyDeletedDocuments = []
            return
        }

        self.directory = directory
        self.recentlyDeletedDirectory = directory
            .appendingPathComponent("Recently Deleted", isDirectory: true)
        storageAvailable = true
        createDirectoryIfNeeded()
        refresh()
    }

    func applyICloudSnapshot(_ snapshots: [ICloudDocumentSnapshot]) {
        let incomingURLs = Set(
            snapshots.map { $0.url.standardizedFileURL }
        )
        suppressedSnapshotURLs.formIntersection(incomingURLs)

        iCloudSnapshotsByURL = Dictionary(
            uniqueKeysWithValues: snapshots.compactMap { snapshot in
                let url = snapshot.url.standardizedFileURL
                guard !suppressedSnapshotURLs.contains(url) else {
                    return nil
                }

                let availability = reconciledAvailability(
                    snapshot.availability,
                    for: url,
                    modified: snapshot.modified
                )
                return (
                    url,
                    ICloudDocumentSnapshot(
                        url: url,
                        created: snapshot.created,
                        modified: snapshot.modified,
                        byteCount: snapshot.byteCount,
                        availability: availability,
                        isRecentlyDeleted: snapshot.isRecentlyDeleted
                    )
                )
            }
        )
        refresh()
    }

    func clearICloudSnapshot() {
        iCloudSnapshotsByURL = [:]
        activeDownloadURLs = []
        confirmedAvailableVersions = [:]
        suppressedSnapshotURLs = []
    }

    private func createDirectoryIfNeeded() {
        guard storageAvailable else { return }
        do {
            try fileAccess.createDirectory(at: directory)
            try fileAccess.createDirectory(at: recentlyDeletedDirectory)
        } catch {
            lastError = "Could not open the ghostWriter folder. \(error.localizedDescription)"
        }
    }

    // MARK: - Reading

    /// Re-reads the directory. Called on appear and whenever the app returns to
    /// the foreground, because files may have changed in the Files app while we
    /// were backgrounded.
    func refresh() {
        guard storageAvailable else { return }
        createDirectoryIfNeeded()

        do {
            let refreshedDocuments = try documents(in: directory)
            if documents != refreshedDocuments {
                documents = refreshedDocuments
            }
        } catch {
            // Keep the last successfully loaded library visible. Replacing it
            // with an empty array would falsely tell the user that their files
            // had disappeared.
            lastError = "Could not refresh the document library. \(error.localizedDescription)"
        }

        do {
            let refreshedDeletedDocuments = try documents(
                in: recentlyDeletedDirectory
            )
            if recentlyDeletedDocuments != refreshedDeletedDocuments {
                recentlyDeletedDocuments = refreshedDeletedDocuments
            }
        } catch {
            lastError = "Could not refresh Recently Deleted. \(error.localizedDescription)"
        }
    }

    private func documents(in directory: URL) throws -> [Document] {
        let keys: [URLResourceKey] = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        let localDocuments = try fileAccess.read(at: directory) {
            coordinatedDirectory in
            let urls = try FileManager.default.contentsOfDirectory(
                at: coordinatedDirectory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            return urls.compactMap(Document.init(fileURL:))
        }

        let isRecentlyDeleted = directory.standardizedFileURL
            == recentlyDeletedDirectory.standardizedFileURL
        let relevantSnapshots = iCloudSnapshotsByURL.values.filter {
            $0.isRecentlyDeleted == isRecentlyDeleted
        }

        var documentsByURL = Dictionary(
            uniqueKeysWithValues: localDocuments.map {
                ($0.url.standardizedFileURL, $0)
            }
        )
        for snapshot in relevantSnapshots {
            let url = snapshot.url.standardizedFileURL
            if let local = documentsByURL[url] {
                documentsByURL[url] = Document(
                    url: url,
                    created: local.created,
                    modified: local.modified,
                    byteCount: local.byteCount,
                    availability: snapshot.availability
                )
            } else {
                documentsByURL[url] = Document(
                    url: url,
                    created: snapshot.created,
                    modified: snapshot.modified,
                    byteCount: snapshot.byteCount,
                    availability: snapshot.availability
                )
            }
        }
        return Array(documentsByURL.values)
    }

    /// Loads a document without turning a read or decoding failure into an empty
    /// document. Callers must handle the error before opening an editable view,
    /// otherwise typing into that view could overwrite the unreadable original.
    func text(for document: Document, reportFailure: Bool = true) throws -> String {
        guard document.availability.isAvailable else {
            if reportFailure {
                lastError =
                    "\(document.displayName) is not yet available on this device."
            }
            throw CocoaError(.fileReadNoSuchFile)
        }

        do {
            let text = try fileAccess.string(at: document.url)
            confirmAvailable(
                at: document.url,
                modified: document.modified
            )
            return text
        } catch {
            if reportFailure {
                lastError = "Could not open \(document.displayName). The original file was not changed. \(error.localizedDescription)"
            }
            throw error
        }
    }

    @discardableResult
    func requestDownload(for document: Document) async -> Bool {
        let url = document.url.standardizedFileURL
        if document.availability.isAvailable {
            confirmAvailable(at: url, modified: document.modified)
            return true
        }
        guard !activeDownloadURLs.contains(url) else { return true }

        activeDownloadURLs.insert(url)
        updateAvailability(
            at: url,
            to: .downloading(percent: nil)
        )

        do {
            try await downloadUbiquitousItem(url)
            guard !Task.isCancelled else {
                activeDownloadURLs.remove(url)
                return false
            }

            activeDownloadURLs.remove(url)
            let modified = Document(fileURL: url)?.modified
                ?? document.modified
            confirmAvailable(at: url, modified: modified)
            updateAvailability(at: url, to: .available)
            return true
        } catch {
            activeDownloadURLs.remove(url)
            guard !Task.isCancelled else { return false }
            let message =
                "Could not download \(document.displayName) from iCloud. \(error.localizedDescription)"
            updateAvailability(at: url, to: .failed(message))
            lastError = message
            return false
        }
    }

    // MARK: - Writing

    /// Compares the current file with the contents the editor last loaded or
    /// successfully saved. Contents are used rather than timestamps because
    /// filesystem timestamp precision differs between storage providers.
    func diskState(for url: URL, expectedContents: String) -> DocumentDiskState {
        guard storageAvailable else { return .unreadable }
        guard fileAccess.itemExists(at: url) else { return .missing }

        do {
            let currentContents = try fileAccess.string(at: url)
            return currentContents == expectedContents
                ? .unchanged
                : .changed(currentContents)
        } catch {
            lastError = "Could not check \(url.deletingPathExtension().lastPathComponent) for changes. \(error.localizedDescription)"
            return .unreadable
        }
    }

    /// Saves only if the file still contains the version the editor expects.
    /// This prevents autosave from silently overwriting changes made in Files
    /// or recreating a document that was deliberately deleted elsewhere.
    func save(
        text: String,
        to url: URL,
        ifUnchangedFrom expectedContents: String
    ) -> GuardedSaveResult {
        switch diskState(for: url, expectedContents: expectedContents) {
        case .unchanged:
            return save(text: text, to: url) ? .saved : .failed
        case .changed(let externalContents):
            return .changedOnDisk(externalContents)
        case .missing:
            return .missing
        case .unreadable:
            return .failed
        }
    }

    /// Writes text to a document. Uses an atomic write so a crash mid-save
    /// cannot leave a half-written file where the user's note used to be.
    /// Writes text to an existing file path. This never creates a second file:
    /// the URL is the identity, and writing to the same URL overwrites it.
    @discardableResult
    func save(text: String, to url: URL) -> Bool {
        guard storageAvailable else {
            lastError = "Could not save because the selected document storage is unavailable."
            return false
        }
        do {
            try fileAccess.write(text, to: url)
            // Deliberately does NOT call refresh(). Refreshing republishes the
            // documents array on every autosave, which churns observed state
            // while the editor is on screen. The library re-reads on appear and
            // on foreground instead.
            return true
        } catch {
            lastError = "Could not save. \(error.localizedDescription)"
            return false
        }
    }

    /// Creates a new file with the given contents, choosing a name that does not
    /// collide with an existing file. Returns the URL it settled on.
    func createDocument(named preferredName: String = "Untitled", contents: String = "") -> URL? {
        guard storageAvailable else {
            lastError = "Could not create a document because the selected document storage is unavailable."
            return nil
        }
        createDirectoryIfNeeded()
        let url = availableURL(for: preferredName)

        do {
            try fileAccess.write(contents, to: url)
            return url
        } catch {
            lastError = "Could not create a new document. \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func moveToRecentlyDeleted(_ document: Document) -> URL? {
        createDirectoryIfNeeded()
        let destination = availableURL(
            forFileName: document.fileName,
            in: recentlyDeletedDirectory
        )

        do {
            try fileAccess.moveItem(at: document.url, to: destination)
            reconcileMove(
                from: document.url,
                to: destination
            )
            refresh()
            return destination
        } catch {
            lastError = "Could not delete \(document.displayName). \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func restore(_ document: Document) -> URL? {
        let destination = availableURL(
            forFileName: document.fileName,
            in: directory
        )

        do {
            try fileAccess.moveItem(at: document.url, to: destination)
            reconcileMove(
                from: document.url,
                to: destination
            )
            refresh()
            return destination
        } catch {
            lastError = "Could not restore \(document.displayName). \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func deletePermanently(_ document: Document) -> Bool {
        do {
            try fileAccess.removeItem(at: document.url)
            suppressSnapshot(at: document.url)
            refresh()
            return true
        } catch {
            lastError = "Could not permanently delete \(document.displayName). \(error.localizedDescription)"
            return false
        }
    }

    /// Renames the file at `url`. Returns the new URL, or nil if it failed.
    /// A no-op rename returns the original URL without touching disk.
    @discardableResult
    func rename(at url: URL, to newName: String) -> URL? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return url }

        let currentName = url.deletingPathExtension().lastPathComponent
        guard trimmed != currentName else { return url }

        let destination = availableURL(for: trimmed)

        do {
            try fileAccess.moveItem(at: url, to: destination)
            reconcileMove(from: url, to: destination)
            refresh()
            return destination
        } catch {
            lastError = "Could not rename to \(trimmed). \(error.localizedDescription)"
            return nil
        }
    }

    func duplicate(_ document: Document) -> Document? {
        let destination = availableURL(for: "\(document.displayName) copy")
        do {
            try fileAccess.copyItem(at: document.url, to: destination)
            refresh()
            return documents.first { $0.url == destination }
        } catch {
            lastError = "Could not duplicate \(document.displayName). \(error.localizedDescription)"
            return nil
        }
    }

    /// Copies selected UTF-8 markdown or text files into the app's own folder.
    /// Reading and rewriting the text keeps imported files independent of their
    /// source and prevents an unreadable file from becoming an empty document.
    func importDocuments(from sourceURLs: [URL]) -> DocumentImportResult {
        createDirectoryIfNeeded()
        var importedURLs: [URL] = []
        var failedNames: [String] = []

        for sourceURL in sourceURLs {
            let fileName = sourceURL.lastPathComponent
            guard Document.isMarkdown(sourceURL) else {
                failedNames.append(fileName)
                continue
            }

            let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try fileAccess.data(at: sourceURL)
                guard let contents = String(data: data, encoding: .utf8) else {
                    failedNames.append(fileName)
                    continue
                }

                let preferredName = sourceURL
                    .deletingPathExtension()
                    .lastPathComponent
                let destination = availableURL(for: preferredName)
                try fileAccess.write(contents, to: destination)
                importedURLs.append(destination)
            } catch {
                failedNames.append(fileName)
            }
        }

        refresh()
        let imported = importedURLs.compactMap { importedURL in
            documents.first { $0.url == importedURL }
        }

        if !failedNames.isEmpty {
            let names = failedNames.joined(separator: ", ")
            lastError = "Could not import \(names). Import markdown or plain-text files saved as UTF-8."
        }

        return DocumentImportResult(
            imported: imported,
            failedFileNames: failedNames
        )
    }

    // MARK: - Naming

    private func reconciledAvailability(
        _ availability: DocumentAvailability,
        for url: URL,
        modified: Date
    ) -> DocumentAvailability {
        if activeDownloadURLs.contains(url) {
            if case .downloading(let percent) = availability {
                return .downloading(percent: percent)
            }
            return .downloading(percent: nil)
        }

        if let confirmed = confirmedAvailableVersions[url] {
            if modified <= confirmed {
                return .available
            }
            confirmedAvailableVersions[url] = nil
        }

        if availability.isAvailable {
            confirmedAvailableVersions[url] = modified
        }
        return availability
    }

    private func confirmAvailable(at url: URL, modified: Date) {
        let standardizedURL = url.standardizedFileURL
        let existing = confirmedAvailableVersions[standardizedURL]
        confirmedAvailableVersions[standardizedURL] = max(
            existing ?? .distantPast,
            modified
        )
    }

    private func suppressSnapshot(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        suppressedSnapshotURLs.insert(standardizedURL)
        iCloudSnapshotsByURL[standardizedURL] = nil
        activeDownloadURLs.remove(standardizedURL)
        confirmedAvailableVersions[standardizedURL] = nil
    }

    private func reconcileMove(from sourceURL: URL, to destinationURL: URL) {
        suppressSnapshot(at: sourceURL)
        let destination = destinationURL.standardizedFileURL
        let modified = Document(fileURL: destination)?.modified
            ?? .distantPast
        confirmAvailable(at: destination, modified: modified)
    }

    private func updateAvailability(
        at url: URL,
        to availability: DocumentAvailability
    ) {
        let standardizedURL = url.standardizedFileURL
        if let snapshot = iCloudSnapshotsByURL[standardizedURL] {
            iCloudSnapshotsByURL[standardizedURL] = ICloudDocumentSnapshot(
                url: snapshot.url,
                created: snapshot.created,
                modified: snapshot.modified,
                byteCount: snapshot.byteCount,
                availability: availability,
                isRecentlyDeleted: snapshot.isRecentlyDeleted
            )
        }

        documents = documents.map { document in
            guard document.url.standardizedFileURL == standardizedURL else {
                return document
            }
            return Document(
                url: document.url,
                created: document.created,
                modified: document.modified,
                byteCount: document.byteCount,
                availability: availability
            )
        }
        recentlyDeletedDocuments = recentlyDeletedDocuments.map { document in
            guard document.url.standardizedFileURL == standardizedURL else {
                return document
            }
            return Document(
                url: document.url,
                created: document.created,
                modified: document.modified,
                byteCount: document.byteCount,
                availability: availability
            )
        }
    }

    /// Strips characters that are illegal in a filename and collapses the rest,
    /// so a heading pasted into the title field cannot produce an unwritable
    /// path or escape the ghostWriter folder.
    static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(120))
    }

    /// Finds a free URL for a name, appending " 2", " 3" and so on if needed.
    private func availableURL(for name: String) -> URL {
        let base = DocumentStore.sanitize(name)
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("md")
        var counter = 2

        while fileAccess.itemExists(at: candidate) {
            candidate = directory
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension("md")
            counter += 1
        }

        return candidate
    }

    /// Finds a free path while preserving an existing document's extension.
    /// Moving to and from Recently Deleted must not silently turn `.txt` or
    /// `.markdown` files into `.md` files.
    private func availableURL(forFileName fileName: String, in directory: URL) -> URL {
        let source = URL(fileURLWithPath: fileName)
        let base = DocumentStore.sanitize(
            source.deletingPathExtension().lastPathComponent
        )
        let pathExtension = source.pathExtension.isEmpty ? "md" : source.pathExtension
        var candidate = directory
            .appendingPathComponent(base)
            .appendingPathExtension(pathExtension)
        var counter = 2

        while fileAccess.itemExists(at: candidate) {
            candidate = directory
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension(pathExtension)
            counter += 1
        }

        return candidate
    }
}
