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
    /// Set when a filesystem operation fails so the UI can surface it rather
    /// than failing silently. Cleared once the user dismisses it.
    var lastError: String?

    private let fileManager = FileManager.default

    /// The user-visible folder. Created on first access; creation failures are
    /// exposed through `lastError` rather than silently changing storage paths.
    let directory: URL
    let recentlyDeletedDirectory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let documentsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = documentsRoot.appendingPathComponent("ghostWriter", isDirectory: true)
        }
        self.recentlyDeletedDirectory = self.directory
            .appendingPathComponent("Recently Deleted", isDirectory: true)
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: recentlyDeletedDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            lastError = "Could not open the ghostWriter folder. \(error.localizedDescription)"
        }
    }

    // MARK: - Reading

    /// Re-reads the directory. Called on appear and whenever the app returns to
    /// the foreground, because files may have changed in the Files app while we
    /// were backgrounded.
    func refresh() {
        createDirectoryIfNeeded()

        do {
            documents = try documents(in: directory)
        } catch {
            // Keep the last successfully loaded library visible. Replacing it
            // with an empty array would falsely tell the user that their files
            // had disappeared.
            lastError = "Could not refresh the document library. \(error.localizedDescription)"
        }

        do {
            recentlyDeletedDocuments = try documents(in: recentlyDeletedDirectory)
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
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap(Document.init(fileURL:))
    }

    /// Loads a document without turning a read or decoding failure into an empty
    /// document. Callers must handle the error before opening an editable view,
    /// otherwise typing into that view could overwrite the unreadable original.
    func text(for document: Document, reportFailure: Bool = true) throws -> String {
        do {
            return try String(contentsOf: document.url, encoding: .utf8)
        } catch {
            if reportFailure {
                lastError = "Could not open \(document.displayName). The original file was not changed. \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - Writing

    /// Compares the current file with the contents the editor last loaded or
    /// successfully saved. Contents are used rather than timestamps because
    /// filesystem timestamp precision differs between storage providers.
    func diskState(for url: URL, expectedContents: String) -> DocumentDiskState {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

        do {
            let currentContents = try String(contentsOf: url, encoding: .utf8)
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
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
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
        createDirectoryIfNeeded()
        let url = availableURL(for: preferredName)

        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
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
            try fileManager.moveItem(at: document.url, to: destination)
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
            try fileManager.moveItem(at: document.url, to: destination)
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
            try fileManager.removeItem(at: document.url)
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
            try fileManager.moveItem(at: url, to: destination)
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
            try fileManager.copyItem(at: document.url, to: destination)
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
                let data = try Data(contentsOf: sourceURL)
                guard let contents = String(data: data, encoding: .utf8) else {
                    failedNames.append(fileName)
                    continue
                }

                let preferredName = sourceURL
                    .deletingPathExtension()
                    .lastPathComponent
                let destination = availableURL(for: preferredName)
                try contents.write(to: destination, atomically: true, encoding: .utf8)
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

        while fileManager.fileExists(atPath: candidate.path) {
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

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension(pathExtension)
            counter += 1
        }

        return candidate
    }
}
