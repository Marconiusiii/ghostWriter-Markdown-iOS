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

nonisolated enum DocumentDiskState: Equatable, Sendable {
    case unchanged
    case changed(String)
    case missing
    case unreadable
}

nonisolated enum GuardedSaveResult: Equatable, Sendable {
    case saved
    case changedOnDisk(String)
    case missing
    case failed
}

struct DocumentImportResult: Equatable {
    let imported: [Document]
    let failedFileNames: [String]
}

/// Carries one completed filesystem scan back to the observable store. The
/// contained models are immutable values; unchecked conformance is limited to
/// this private transfer object because Document predates explicit Sendable
/// conformance.
private nonisolated struct DocumentLibraryScan: @unchecked Sendable {
    let documents: [Document]?
    let folders: [LibraryFolder]?
    let recentlyDeletedDocuments: [Document]?
    let recentlyDeletedFolders: [LibraryFolder]?
    let errors: [String]
}

private nonisolated enum DocumentTextReadOutcome: Sendable {
    case success(String)
    case failure(String)
}

@Observable
final class DocumentStore {
    private(set) var libraryPresentationRevision = 0
    private(set) var documents: [Document] = [] {
        didSet { libraryPresentationRevision &+= 1 }
    }
    private(set) var folders: [LibraryFolder] = [] {
        didSet { libraryPresentationRevision &+= 1 }
    }
    private(set) var recentlyDeletedDocuments: [Document] = []
    private(set) var recentlyDeletedFolders: [LibraryFolder] = []
    private(set) var storageAvailable: Bool
    private(set) var usesICloudStorage: Bool
    /// Set when a filesystem operation fails so the UI can surface it rather
    /// than failing silently. Cleared once the user dismisses it.
    var lastError: String?

    private let fileAccess: CoordinatedFileAccess
    private let saveQueue = CoordinatedDocumentSaveQueue()
    private let downloadUbiquitousItem: (URL) async throws -> Void
    private let placeUbiquitousItem: (Data, URL) async throws -> Void
    private var iCloudSnapshotsByURL: [URL: ICloudDocumentSnapshot] = [:]
    private var activeDownloadURLs: Set<URL> = []
    private var confirmedAvailableVersions: [URL: Date] = [:]
    private var suppressedSnapshotURLs: Set<URL> = []
    private var refreshGeneration = 0

    /// The user-visible folder. Created on first access; creation failures are
    /// exposed through `lastError` rather than silently changing storage paths.
    private(set) var directory: URL
    private(set) var recentlyDeletedDirectory: URL

    init(
        directory: URL? = nil,
        storageAvailable: Bool = true,
        usesICloudStorage: Bool = false,
        fileAccess: CoordinatedFileAccess = CoordinatedFileAccess(),
        startDownloadingUbiquitousItem:
            @escaping (URL) async throws -> Void = {
                try await CoordinatedFileAccess
                    .downloadAndVerifyUbiquitousItem(at: $0)
            },
        placeUbiquitousItem:
            @escaping (Data, URL) async throws -> Void = {
                try await CoordinatedFileAccess.placeUbiquitousItem(
                    data: $0,
                    at: $1
                )
        }
    ) {
        self.storageAvailable = storageAvailable
        self.usesICloudStorage = usesICloudStorage
        self.fileAccess = fileAccess
        self.downloadUbiquitousItem =
            startDownloadingUbiquitousItem
        self.placeUbiquitousItem = placeUbiquitousItem
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

    func useDirectory(
        _ directory: URL?,
        usesICloudStorage: Bool = false
    ) {
        self.usesICloudStorage = usesICloudStorage
        guard let directory else {
            storageAvailable = false
            documents = []
            folders = []
            recentlyDeletedDocuments = []
            recentlyDeletedFolders = []
            return
        }

        self.directory = directory
        self.recentlyDeletedDirectory = directory
            .appendingPathComponent("Recently Deleted", isDirectory: true)
        storageAvailable = true
        createDirectoryIfNeeded()
        refresh()
    }

    func useDirectoryAsynchronously(
        _ directory: URL?,
        usesICloudStorage: Bool = false
    ) async {
        self.usesICloudStorage = usesICloudStorage
        guard let directory else {
            refreshGeneration &+= 1
            storageAvailable = false
            documents = []
            folders = []
            recentlyDeletedDocuments = []
            recentlyDeletedFolders = []
            return
        }

        self.directory = directory
        self.recentlyDeletedDirectory = directory
            .appendingPathComponent("Recently Deleted", isDirectory: true)
        storageAvailable = true
        createDirectoryIfNeeded()
        await refreshAsynchronously()
    }

    func applyICloudSnapshot(_ snapshots: [ICloudDocumentSnapshot]) {
        updateICloudSnapshot(snapshots)
        refresh()
    }

    func applyICloudSnapshotAsynchronously(
        _ snapshots: [ICloudDocumentSnapshot]
    ) async {
        updateICloudSnapshot(snapshots)
        await refreshAsynchronously()
    }

    private func updateICloudSnapshot(
        _ snapshots: [ICloudDocumentSnapshot]
    ) {
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
        refreshGeneration &+= 1
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
            let refreshedFolders = try libraryFolders()
            if folders != refreshedFolders {
                folders = refreshedFolders
            }
        } catch {
            lastError = "Could not refresh the folder library. \(error.localizedDescription)"
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


        do {
            let urls = try fileAccess.contentsOfDirectory(
                at: recentlyDeletedDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            recentlyDeletedFolders = urls.compactMap(LibraryFolder.init(fileURL:))
        } catch {
            lastError = "Could not refresh deleted folders. \(error.localizedDescription)"
        }
    }

    /// Performs coordinated directory enumeration away from the main actor,
    /// then publishes at most one result for each observable collection.
    func refreshAsynchronously() async {
        guard storageAvailable else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let directory = directory
        let recentlyDeletedDirectory = recentlyDeletedDirectory
        let snapshots = Array(iCloudSnapshotsByURL.values)

        let scanTask = Task.detached(priority: .utility) {
            Self.scanLibrary(
                directory: directory,
                recentlyDeletedDirectory: recentlyDeletedDirectory,
                snapshots: snapshots
            )
        }
        let scan = await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }

        guard !Task.isCancelled,
              generation == refreshGeneration,
              storageAvailable,
              self.directory.standardizedFileURL
                == directory.standardizedFileURL else { return }

        if let refreshed = scan.documents, documents != refreshed {
            documents = refreshed
        }
        if let refreshed = scan.folders, folders != refreshed {
            folders = refreshed
        }
        if let refreshed = scan.recentlyDeletedDocuments,
           recentlyDeletedDocuments != refreshed {
            recentlyDeletedDocuments = refreshed
        }
        if let refreshed = scan.recentlyDeletedFolders,
           recentlyDeletedFolders != refreshed {
            recentlyDeletedFolders = refreshed
        }
        if let error = scan.errors.last {
            lastError = error
        }
    }

    func cancelPendingRefresh() {
        refreshGeneration &+= 1
    }

    private nonisolated static func scanLibrary(
        directory: URL,
        recentlyDeletedDirectory: URL,
        snapshots: [ICloudDocumentSnapshot]
    ) -> DocumentLibraryScan {
        let fileAccess = CoordinatedFileAccess()
        var errors: [String] = []

        guard !Task.isCancelled else {
            return DocumentLibraryScan(
                documents: nil,
                folders: nil,
                recentlyDeletedDocuments: nil,
                recentlyDeletedFolders: nil,
                errors: []
            )
        }

        let documents: [Document]?
        do {
            documents = try scannedDocuments(
                in: directory,
                libraryRoot: directory,
                recentlyDeletedDirectory: recentlyDeletedDirectory,
                snapshots: snapshots,
                fileAccess: fileAccess
            )
        } catch {
            documents = nil
            errors.append(
                "Could not refresh the document library. \(error.localizedDescription)"
            )
        }

        guard !Task.isCancelled else {
            return DocumentLibraryScan(
                documents: nil,
                folders: nil,
                recentlyDeletedDocuments: nil,
                recentlyDeletedFolders: nil,
                errors: []
            )
        }

        let folders: [LibraryFolder]?
        do {
            folders = try scannedFolders(
                directory: directory,
                recentlyDeletedDirectory: recentlyDeletedDirectory,
                snapshots: snapshots,
                fileAccess: fileAccess
            )
        } catch {
            folders = nil
            errors.append(
                "Could not refresh the folder library. \(error.localizedDescription)"
            )
        }

        guard !Task.isCancelled else {
            return DocumentLibraryScan(
                documents: nil,
                folders: nil,
                recentlyDeletedDocuments: nil,
                recentlyDeletedFolders: nil,
                errors: []
            )
        }

        let deletedDocuments: [Document]?
        do {
            deletedDocuments = try scannedDocuments(
                in: recentlyDeletedDirectory,
                libraryRoot: directory,
                recentlyDeletedDirectory: recentlyDeletedDirectory,
                snapshots: snapshots,
                fileAccess: fileAccess
            )
        } catch {
            deletedDocuments = nil
            errors.append(
                "Could not refresh Recently Deleted. \(error.localizedDescription)"
            )
        }

        guard !Task.isCancelled else {
            return DocumentLibraryScan(
                documents: nil,
                folders: nil,
                recentlyDeletedDocuments: nil,
                recentlyDeletedFolders: nil,
                errors: []
            )
        }

        let deletedFolders: [LibraryFolder]?
        do {
            let urls = try fileAccess.contentsOfDirectory(
                at: recentlyDeletedDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            deletedFolders = urls.compactMap(LibraryFolder.init(fileURL:))
        } catch {
            deletedFolders = nil
            errors.append(
                "Could not refresh deleted folders. \(error.localizedDescription)"
            )
        }

        return DocumentLibraryScan(
            documents: documents,
            folders: folders,
            recentlyDeletedDocuments: deletedDocuments,
            recentlyDeletedFolders: deletedFolders,
            errors: errors
        )
    }

    private nonisolated static func scannedDocuments(
        in scanDirectory: URL,
        libraryRoot: URL,
        recentlyDeletedDirectory: URL,
        snapshots: [ICloudDocumentSnapshot],
        fileAccess: CoordinatedFileAccess
    ) throws -> [Document] {
        let isLibraryRoot = scanDirectory.standardizedFileURL
            == libraryRoot.standardizedFileURL
        let isRecentlyDeleted = scanDirectory.standardizedFileURL
            == recentlyDeletedDirectory.standardizedFileURL
        let urls = isRecentlyDeleted
            ? try fileAccess.contentsOfDirectory(
                at: scanDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            : try fileAccess.regularFilesRecursively(at: scanDirectory)
        let localDocuments = urls.filter { url in
            guard Document.isMarkdown(url) else { return false }
            guard isLibraryRoot else { return true }
            return !isDescendant(url, of: recentlyDeletedDirectory)
        }.compactMap(Document.init(fileURL:))

        var documentsByURL = Dictionary(
            uniqueKeysWithValues: localDocuments.map {
                ($0.url.standardizedFileURL, $0)
            }
        )
        for snapshot in snapshots
        where snapshot.isRecentlyDeleted == isRecentlyDeleted {
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

    private nonisolated static func scannedFolders(
        directory: URL,
        recentlyDeletedDirectory: URL,
        snapshots: [ICloudDocumentSnapshot],
        fileAccess: CoordinatedFileAccess
    ) throws -> [LibraryFolder] {
        var urls = try fileAccess.directoriesRecursively(at: directory)
            .filter {
                $0.standardizedFileURL
                    != recentlyDeletedDirectory.standardizedFileURL
                    && !isDescendant($0, of: recentlyDeletedDirectory)
            }
        for snapshot in snapshots where !snapshot.isRecentlyDeleted {
            var parent = snapshot.url.deletingLastPathComponent()
            while parent.standardizedFileURL != directory.standardizedFileURL,
                  isDescendant(parent, of: directory) {
                urls.append(parent)
                parent.deleteLastPathComponent()
            }
        }
        var foldersByURL: [URL: LibraryFolder] = [:]
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            foldersByURL[standardizedURL] =
                LibraryFolder(fileURL: standardizedURL)
                ?? LibraryFolder(url: standardizedURL)
        }
        return Array(foldersByURL.values)
    }

    private func documents(in directory: URL) throws -> [Document] {
        let isLibraryRoot = directory.standardizedFileURL
            == self.directory.standardizedFileURL
        let isRecentlyDeleted = directory.standardizedFileURL
            == recentlyDeletedDirectory.standardizedFileURL
        let urls: [URL]
        if isRecentlyDeleted {
            urls = try fileAccess.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        } else {
            urls = try fileAccess.regularFilesRecursively(at: directory)
        }
        let localDocuments = urls.filter { url in
            guard Document.isMarkdown(url) else { return false }
            guard isLibraryRoot else { return true }
            return !Self.isDescendant(url, of: recentlyDeletedDirectory)
        }.compactMap(Document.init(fileURL:))

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

    private func libraryFolders() throws -> [LibraryFolder] {
        var urls = try fileAccess.directoriesRecursively(at: directory)
            .filter {
                $0.standardizedFileURL
                    != recentlyDeletedDirectory.standardizedFileURL
                    && !Self.isDescendant($0, of: recentlyDeletedDirectory)
            }
        for snapshot in iCloudSnapshotsByURL.values where !snapshot.isRecentlyDeleted {
            var parent = snapshot.url.deletingLastPathComponent()
            while parent.standardizedFileURL != directory.standardizedFileURL,
                  Self.isDescendant(parent, of: directory) {
                urls.append(parent)
                parent.deleteLastPathComponent()
            }
        }
        var foldersByURL: [URL: LibraryFolder] = [:]
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            foldersByURL[standardizedURL] =
                LibraryFolder(fileURL: standardizedURL)
                ?? LibraryFolder(url: standardizedURL)
        }
        return Array(foldersByURL.values)
    }

    func documents(directlyIn folderURL: URL) -> [Document] {
        documents.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL
                == folderURL.standardizedFileURL
        }
    }

    func folders(directlyIn folderURL: URL) -> [LibraryFolder] {
        folders.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL
                == folderURL.standardizedFileURL
        }
    }

    func itemCount(in folder: LibraryFolder) -> Int {
        documents(directlyIn: folder.url).count
            + folders(directlyIn: folder.url).count
    }

    func containingDirectory(for itemURL: URL) -> URL {
        let parent = itemURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard isLibraryDirectory(parent),
              FileManager.default.fileExists(
                atPath: parent.path,
                isDirectory: &isDirectory
              ),
              isDirectory.boolValue else {
            return directory
        }
        return parent
    }

    func documentMovePairs(
        fromFolder sourceFolder: URL,
        toFolder destinationFolder: URL
    ) -> [DocumentMigrationPair] {
        guard let files = try? fileAccess.regularFilesRecursively(at: sourceFolder) else {
            return []
        }
        return files.filter(Document.isMarkdown).map { sourceURL in
            let relativeComponents = sourceURL.standardizedFileURL.pathComponents
                .dropFirst(sourceFolder.standardizedFileURL.pathComponents.count)
            let destinationURL = relativeComponents.reduce(destinationFolder) {
                $0.appendingPathComponent($1)
            }
            return DocumentMigrationPair(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        }
    }

    var recentlyDeletedItems: [DeletedLibraryItem] {
        recentlyDeletedDocuments.map {
            DeletedLibraryItem(
                item: .document($0),
                originalRelativePath: deletionRecord(for: $0.url)?.originalRelativePath
            )
        } + recentlyDeletedFolders.map {
            DeletedLibraryItem(
                item: .folder($0),
                originalRelativePath: deletionRecord(for: $0.url)?.originalRelativePath
            )
        }
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

    /// Coordinates and decodes a document away from the main actor so opening
    /// a file cannot stall VoiceOver or the rest of the Library interface.
    func textAsynchronously(
        for document: Document,
        reportFailure: Bool = true
    ) async throws -> String {
        guard document.availability.isAvailable else {
            if reportFailure {
                lastError =
                    "\(document.displayName) is not yet available on this device."
            }
            throw CocoaError(.fileReadNoSuchFile)
        }

        let url = document.url
        let outcome = await Task.detached(priority: .userInitiated) {
            do {
                return DocumentTextReadOutcome.success(
                    try CoordinatedFileAccess().string(at: url)
                )
            } catch {
                return DocumentTextReadOutcome.failure(
                    error.localizedDescription
                )
            }
        }.value

        try Task.checkCancellation()
        switch outcome {
        case .success(let text):
            confirmAvailable(at: url, modified: document.modified)
            return text
        case .failure(let message):
            if reportFailure {
                lastError = "Could not open \(document.displayName). The original file was not changed. \(message)"
            }
            throw CocoaError(.fileReadUnknown)
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

    func diskStateAsynchronously(
        for url: URL,
        expectedContents: String
    ) async -> DocumentDiskState {
        guard storageAvailable else { return .unreadable }

        switch await saveQueue.diskState(
            at: url,
            expectedContents: expectedContents
        ) {
        case .saved:
            return .unchanged
        case .changedOnDisk(let externalContents):
            return .changed(externalContents)
        case .missing:
            return .missing
        case .failed(let message):
            lastError = "Could not check \(url.deletingPathExtension().lastPathComponent) for changes. \(message)"
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

    /// Performs the complete guarded-save transaction on a dedicated actor.
    /// NSFileCoordinator is synchronous and can wait for iCloud, so calling the
    /// synchronous save path from the editor would block all text input.
    func saveAsynchronously(
        text: String,
        to url: URL,
        ifUnchangedFrom expectedContents: String
    ) async -> GuardedSaveResult {
        guard storageAvailable else {
            lastError = "Could not save because the selected document storage is unavailable."
            return .failed
        }

        switch await saveQueue.save(
            text: text,
            to: url,
            ifUnchangedFrom: expectedContents
        ) {
        case .saved:
            return .saved
        case .changedOnDisk(let externalContents):
            return .changedOnDisk(externalContents)
        case .missing:
            return .missing
        case .failed(let message):
            lastError = "Could not save. \(message)"
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
        guard !usesICloudStorage else {
            lastError =
                "Could not create a new document because iCloud placement was not started."
            return nil
        }
        return createLocalDocument(
            named: preferredName,
            contents: contents
        )
    }

    private func createLocalDocument(
        named preferredName: String,
        contents: String,
        in destinationDirectory: URL? = nil
    ) -> URL? {
        guard storageAvailable else {
            lastError = "Could not create a document because the selected document storage is unavailable."
            return nil
        }
        createDirectoryIfNeeded()
        let targetDirectory = destinationDirectory ?? directory
        do {
            try fileAccess.createDirectory(at: targetDirectory)
        } catch {
            lastError = "Could not open the destination folder. \(error.localizedDescription)"
            return nil
        }
        let url = availableURL(
            for: preferredName,
            in: targetDirectory
        )

        do {
            try fileAccess.write(contents, to: url)
            return url
        } catch {
            lastError = "Could not create a new document. \(error.localizedDescription)"
            return nil
        }
    }

    /// Creates a new local file directly, or stages a complete iCloud file
    /// locally before registering it with the ubiquity container.
    func createDocument(
        named preferredName: String = "Untitled",
        contents: String = "",
        in destinationDirectory: URL? = nil
    ) async -> URL? {
        guard usesICloudStorage else {
            return createLocalDocument(
                named: preferredName,
                contents: contents,
                in: destinationDirectory
            )
        }
        guard storageAvailable else {
            lastError =
                "Could not create a document because the selected document storage is unavailable."
            return nil
        }

        createDirectoryIfNeeded()
        let targetDirectory = destinationDirectory ?? directory
        do {
            try fileAccess.createDirectory(at: targetDirectory)
        } catch {
            lastError = "Could not open the destination folder. \(error.localizedDescription)"
            return nil
        }
        let url = availableURL(
            for: preferredName,
            in: targetDirectory
        )
        do {
            try await placeUbiquitousItem(Data(contents.utf8), url)
            refresh()
            return url
        } catch {
            lastError =
                "Could not create a new document in iCloud. \(error.localizedDescription)"
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
            try writeDeletionRecord(
                originalURL: document.url,
                deletedURL: destination
            )
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
        let destination = restorationURL(
            for: document.url,
            fallbackFileName: document.fileName
        )

        do {
            try fileAccess.moveItem(at: document.url, to: destination)
            removeDeletionRecord(for: document.url)
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
            removeDeletionRecord(for: document.url)
            suppressSnapshot(at: document.url)
            refresh()
            return true
        } catch {
            lastError = "Could not permanently delete \(document.displayName). \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func createFolder(named preferredName: String, in parent: URL) -> LibraryFolder? {
        guard isLibraryDirectory(parent) else {
            lastError = "Could not create a folder outside the document library."
            return nil
        }
        let destination = availableFolderURL(for: preferredName, in: parent)
        do {
            try fileAccess.createDirectory(at: destination)
            refresh()
            return LibraryFolder(fileURL: destination) ?? LibraryFolder(url: destination)
        } catch {
            lastError = "Could not create the folder. \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func rename(_ folder: LibraryFolder, to newName: String) -> URL? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.displayName else {
            return folder.url
        }
        let destination = availableFolderURL(
            for: trimmed,
            in: folder.url.deletingLastPathComponent()
        )
        return moveFolder(folder, to: destination, failureVerb: "rename")
    }

    @discardableResult
    func move(_ item: LibraryItem, to destinationDirectory: URL) -> URL? {
        guard isLibraryDirectory(destinationDirectory) else {
            lastError = "Could not move \(item.displayName) outside the document library."
            return nil
        }
        switch item {
        case .document(let document):
            let destination = availableURL(
                forFileName: document.fileName,
                in: destinationDirectory
            )
            do {
                try fileAccess.moveItem(at: document.url, to: destination)
                reconcileMove(from: document.url, to: destination)
                refresh()
                return destination
            } catch {
                lastError = "Could not move \(document.displayName). \(error.localizedDescription)"
                return nil
            }
        case .folder(let folder):
            guard destinationDirectory.standardizedFileURL
                    != folder.url.standardizedFileURL,
                  !Self.isDescendant(destinationDirectory, of: folder.url) else {
                lastError = "A folder cannot be moved inside itself."
                return nil
            }
            let destination = availableFolderURL(
                for: folder.displayName,
                in: destinationDirectory
            )
            return moveFolder(folder, to: destination, failureVerb: "move")
        }
    }

    @discardableResult
    func moveToRecentlyDeleted(_ folder: LibraryFolder) -> URL? {
        let destination = availableFolderURL(
            for: folder.displayName,
            in: recentlyDeletedDirectory
        )
        do {
            try fileAccess.moveItem(at: folder.url, to: destination)
            try writeDeletionRecord(originalURL: folder.url, deletedURL: destination)
            suppressSnapshots(beneath: folder.url)
            refresh()
            return destination
        } catch {
            lastError = "Could not delete \(folder.displayName). \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func restore(_ folder: LibraryFolder) -> URL? {
        let destination = restorationURL(
            for: folder.url,
            fallbackFolderName: folder.displayName
        )
        do {
            try fileAccess.moveItem(at: folder.url, to: destination)
            removeDeletionRecord(for: folder.url)
            refresh()
            return destination
        } catch {
            lastError = "Could not restore \(folder.displayName). \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func deletePermanently(_ folder: LibraryFolder) -> Bool {
        do {
            try fileAccess.removeItem(at: folder.url)
            removeDeletionRecord(for: folder.url)
            suppressSnapshots(beneath: folder.url)
            refresh()
            return true
        } catch {
            lastError = "Could not permanently delete \(folder.displayName). \(error.localizedDescription)"
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

        let destination = availableURL(
            for: trimmed,
            in: url.deletingLastPathComponent()
        )

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
        guard !usesICloudStorage else {
            lastError =
                "Could not duplicate \(document.displayName) because iCloud placement was not started."
            return nil
        }
        return duplicateLocally(document)
    }

    private func duplicateLocally(_ document: Document) -> Document? {
        let destination = availableURL(
            for: "\(document.displayName) copy",
            in: document.url.deletingLastPathComponent()
        )
        do {
            try fileAccess.copyItem(at: document.url, to: destination)
            refresh()
            return documents.first { $0.url == destination }
        } catch {
            lastError = "Could not duplicate \(document.displayName). \(error.localizedDescription)"
            return nil
        }
    }

    func duplicate(_ document: Document) async -> Document? {
        guard usesICloudStorage else {
            return duplicateLocally(document)
        }

        let destination = availableURL(
            for: "\(document.displayName) copy",
            in: document.url.deletingLastPathComponent()
        )
        do {
            let data = try fileAccess.data(at: document.url)
            try await placeUbiquitousItem(data, destination)
            refresh()
            return documents.first { $0.url == destination }
        } catch {
            lastError =
                "Could not duplicate \(document.displayName) in iCloud. \(error.localizedDescription)"
            return nil
        }
    }

    /// Copies selected Markdown, text, or Word documents into the app's folder.
    /// Word content is converted before placement, and every imported file is
    /// validated before a destination document is created.
    func importDocuments(
        from sourceURLs: [URL],
        into destinationDirectory: URL? = nil
    ) -> DocumentImportResult {
        guard !usesICloudStorage else {
            lastError =
                "Could not import documents because iCloud placement was not started."
            return DocumentImportResult(
                imported: [],
                failedFileNames: sourceURLs.map(\.lastPathComponent)
            )
        }
        return importDocumentsLocally(
            from: sourceURLs,
            into: destinationDirectory
        )
    }

    private func importDocumentsLocally(
        from sourceURLs: [URL],
        into destinationDirectory: URL? = nil
    ) -> DocumentImportResult {
        createDirectoryIfNeeded()
        let targetDirectory = destinationDirectory ?? directory
        do {
            try fileAccess.createDirectory(at: targetDirectory)
        } catch {
            lastError = "Could not open the destination folder. \(error.localizedDescription)"
            return DocumentImportResult(
                imported: [],
                failedFileNames: sourceURLs.map(\.lastPathComponent)
            )
        }
        var importedURLs: [URL] = []
        var failedNames: [String] = []
        var failureDetails: [String] = []

        for sourceURL in sourceURLs {
            let fileName = sourceURL.lastPathComponent
            guard Self.isImportableDocument(sourceURL) else {
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
                let contents = try Self.importedMarkdown(
                    from: data,
                    sourceURL: sourceURL
                )

                let preferredName = sourceURL
                    .deletingPathExtension()
                    .lastPathComponent
                let destination = availableURL(
                    for: preferredName,
                    in: targetDirectory
                )
                try fileAccess.write(contents, to: destination)
                importedURLs.append(destination)
            } catch {
                failedNames.append(fileName)
                failureDetails.append(Self.importFailureDescription(
                    fileName: fileName,
                    sourceURL: sourceURL,
                    error: error
                ))
            }
        }

        refresh()
        let imported = importedURLs.compactMap { importedURL in
            documents.first { $0.url == importedURL }
        }

        if !failedNames.isEmpty {
            let names = failedNames.joined(separator: ", ")
            let detail = failureDetails.isEmpty
                ? "Import Markdown or plain-text files saved as UTF-8, or Word documents saved as .docx."
                : failureDetails.joined(separator: " ")
            lastError = "Could not import \(names). \(detail)"
        }

        return DocumentImportResult(
            imported: imported,
            failedFileNames: failedNames
        )
    }

    func importDocuments(
        from sourceURLs: [URL],
        into destinationDirectory: URL? = nil
    ) async -> DocumentImportResult {
        guard usesICloudStorage else {
            return await importDocumentsLocallyAwayFromTyping(
                from: sourceURLs,
                into: destinationDirectory
            )
        }

        createDirectoryIfNeeded()
        let targetDirectory = destinationDirectory ?? directory
        do {
            try fileAccess.createDirectory(at: targetDirectory)
        } catch {
            lastError = "Could not open the destination folder. \(error.localizedDescription)"
            return DocumentImportResult(
                imported: [],
                failedFileNames: sourceURLs.map(\.lastPathComponent)
            )
        }
        var importedURLs: [URL] = []
        var failedNames: [String] = []
        var failureDetails: [String] = []

        for sourceURL in sourceURLs {
            let fileName = sourceURL.lastPathComponent
            guard Self.isImportableDocument(sourceURL) else {
                failedNames.append(fileName)
                continue
            }

            let hasScopedAccess =
                sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try fileAccess.data(at: sourceURL)
                let contents = try await Self.importedMarkdownAwayFromTyping(
                    from: data,
                    sourceURL: sourceURL
                )

                let preferredName = sourceURL
                    .deletingPathExtension()
                    .lastPathComponent
                let destination = availableURL(
                    for: preferredName,
                    in: targetDirectory
                )
                try await placeUbiquitousItem(Data(contents.utf8), destination)
                importedURLs.append(destination)
            } catch {
                failedNames.append(fileName)
                failureDetails.append(Self.importFailureDescription(
                    fileName: fileName,
                    sourceURL: sourceURL,
                    error: error
                ))
            }
        }

        refresh()
        let imported = importedURLs.compactMap { importedURL in
            documents.first { $0.url == importedURL }
        }

        if !failedNames.isEmpty {
            let names = failedNames.joined(separator: ", ")
            let detail = failureDetails.isEmpty
                ? "Import Markdown or plain-text files saved as UTF-8, or Word documents saved as .docx."
                : failureDetails.joined(separator: " ")
            lastError = "Could not import \(names). \(detail)"
        }

        return DocumentImportResult(
            imported: imported,
            failedFileNames: failedNames
        )
    }

    private nonisolated static func isImportableDocument(_ url: URL) -> Bool {
        Document.isMarkdown(url) || url.pathExtension.lowercased() == "docx"
    }

    private func importDocumentsLocallyAwayFromTyping(
        from sourceURLs: [URL],
        into destinationDirectory: URL?
    ) async -> DocumentImportResult {
        createDirectoryIfNeeded()
        let targetDirectory = destinationDirectory ?? directory
        do {
            try fileAccess.createDirectory(at: targetDirectory)
        } catch {
            lastError = "Could not open the destination folder. \(error.localizedDescription)"
            return DocumentImportResult(
                imported: [],
                failedFileNames: sourceURLs.map(\.lastPathComponent)
            )
        }

        var importedURLs: [URL] = []
        var failedNames: [String] = []
        var failureDetails: [String] = []
        for sourceURL in sourceURLs {
            let fileName = sourceURL.lastPathComponent
            guard Self.isImportableDocument(sourceURL) else {
                failedNames.append(fileName)
                continue
            }
            let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try fileAccess.data(at: sourceURL)
                let contents = try await Self.importedMarkdownAwayFromTyping(
                    from: data,
                    sourceURL: sourceURL
                )
                let preferredName = sourceURL.deletingPathExtension().lastPathComponent
                let destination = availableURL(for: preferredName, in: targetDirectory)
                try fileAccess.write(contents, to: destination)
                importedURLs.append(destination)
            } catch {
                failedNames.append(fileName)
                failureDetails.append(Self.importFailureDescription(
                    fileName: fileName,
                    sourceURL: sourceURL,
                    error: error
                ))
            }
        }

        refresh()
        let imported = importedURLs.compactMap { importedURL in
            documents.first { $0.url == importedURL }
        }
        if !failedNames.isEmpty {
            let names = failedNames.joined(separator: ", ")
            let detail = failureDetails.isEmpty
                ? "Import Markdown or plain-text files saved as UTF-8, or Word documents saved as .docx."
                : failureDetails.joined(separator: " ")
            lastError = "Could not import \(names). \(detail)"
        }
        return DocumentImportResult(imported: imported, failedFileNames: failedNames)
    }

    private nonisolated static func importedMarkdownAwayFromTyping(
        from data: Data,
        sourceURL: URL
    ) async throws -> String {
        if sourceURL.pathExtension.lowercased() != "docx" {
            return try importedMarkdown(from: data, sourceURL: sourceURL)
        }
        return try await Task.detached(priority: .userInitiated) {
            try WordToMarkdownConverter.convert(data: data)
        }.value
    }

    private nonisolated static func importFailureDescription(
        fileName: String,
        sourceURL: URL,
        error: Error
    ) -> String {
        if sourceURL.pathExtension.lowercased() == "docx" {
            return "\(fileName): \(error.localizedDescription)"
        }
        return "\(fileName): The text file must use UTF-8 encoding."
    }

    private nonisolated static func importedMarkdown(
        from data: Data,
        sourceURL: URL
    ) throws -> String {
        if sourceURL.pathExtension.lowercased() == "docx" {
            return try WordToMarkdownConverter.convert(data: data)
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return contents
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

        if availability.reportsUploadState {
            confirmedAvailableVersions[url] = max(
                confirmedAvailableVersions[url] ?? .distantPast,
                modified
            )
            return availability
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

    private func moveFolder(
        _ folder: LibraryFolder,
        to destination: URL,
        failureVerb: String
    ) -> URL? {
        do {
            try fileAccess.moveItem(at: folder.url, to: destination)
            suppressSnapshots(beneath: folder.url)
            refresh()
            return destination
        } catch {
            lastError = "Could not \(failureVerb) \(folder.displayName). \(error.localizedDescription)"
            return nil
        }
    }

    private func suppressSnapshots(beneath folderURL: URL) {
        let affectedURLs = iCloudSnapshotsByURL.keys.filter {
            Self.isDescendant($0, of: folderURL)
        }
        affectedURLs.forEach { suppressSnapshot(at: $0) }
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
    private func availableURL(for name: String, in directory: URL) -> URL {
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

    private func availableFolderURL(for name: String, in directory: URL) -> URL {
        let base = DocumentStore.sanitize(name)
        var candidate = directory.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while fileAccess.itemExists(at: candidate) {
            candidate = directory.appendingPathComponent(
                "\(base) \(counter)",
                isDirectory: true
            )
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

    private func deletionRecordURL(for deletedURL: URL) -> URL {
        recentlyDeletedDirectory.appendingPathComponent(
            ".ghostwriter-\(deletedURL.lastPathComponent).json"
        )
    }

    private func writeDeletionRecord(originalURL: URL, deletedURL: URL) throws {
        let record = DeletedItemRecord(
            originalRelativePath: relativePath(for: originalURL)
        )
        try fileAccess.write(
            JSONEncoder().encode(record),
            to: deletionRecordURL(for: deletedURL)
        )
    }

    private func deletionRecord(for deletedURL: URL) -> DeletedItemRecord? {
        try? JSONDecoder().decode(
            DeletedItemRecord.self,
            from: fileAccess.data(at: deletionRecordURL(for: deletedURL))
        )
    }

    private func removeDeletionRecord(for deletedURL: URL) {
        let recordURL = deletionRecordURL(for: deletedURL)
        guard fileAccess.itemExists(at: recordURL) else { return }
        try? fileAccess.removeItem(at: recordURL)
    }

    private func restorationParent(for deletedURL: URL) -> URL {
        guard let record = deletionRecord(for: deletedURL) else { return directory }
        let originalURL = directory.appendingPathComponent(record.originalRelativePath)
        let parent = originalURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard isLibraryDirectory(parent),
              FileManager.default.fileExists(
                atPath: parent.path,
                isDirectory: &isDirectory
              ),
              isDirectory.boolValue else {
            return directory
        }
        return parent
    }

    private func restorationURL(for deletedURL: URL, fallbackFileName: String) -> URL {
        availableURL(
            forFileName: fallbackFileName,
            in: restorationParent(for: deletedURL)
        )
    }

    private func restorationURL(for deletedURL: URL, fallbackFolderName: String) -> URL {
        availableFolderURL(
            for: fallbackFolderName,
            in: restorationParent(for: deletedURL)
        )
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = directory.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return itemPath.hasPrefix(prefix)
            ? String(itemPath.dropFirst(prefix.count))
            : url.lastPathComponent
    }

    private func isLibraryDirectory(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        return standardized == directory.standardizedFileURL
            || (Self.isDescendant(standardized, of: directory)
                && standardized != recentlyDeletedDirectory.standardizedFileURL
                && !Self.isDescendant(standardized, of: recentlyDeletedDirectory))
    }

    private nonisolated static func isDescendant(
        _ candidate: URL,
        of ancestor: URL
    ) -> Bool {
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > ancestorComponents.count
            && candidateComponents.starts(with: ancestorComponents)
    }
}
