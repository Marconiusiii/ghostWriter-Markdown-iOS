//
//  CoordinatedFileAccess.swift
//  ghostWriter
//
//  All document operations pass through NSFileCoordinator. This is required
//  for iCloud documents and also coordinates with Files and other presenters
//  when the user keeps the library locally.
//

import Foundation

nonisolated enum CoordinatedGuardedSaveOutcome: Sendable {
    case saved
    case changedOnDisk(String)
    case missing
    case failed(String)
}

/// Serializes guarded document saves away from the main actor. File
/// coordination may wait for iCloud or another file presenter, so none of this
/// work can share the executor that handles UIKit text input.
actor CoordinatedDocumentSaveQueue {
    private let fileAccess = CoordinatedFileAccess()

    func diskState(
        at url: URL,
        expectedContents: String
    ) -> CoordinatedGuardedSaveOutcome {
        guard fileAccess.itemExists(at: url) else { return .missing }

        do {
            let currentContents = try fileAccess.string(at: url)
            return currentContents == expectedContents
                ? .saved
                : .changedOnDisk(currentContents)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func save(
        text: String,
        to url: URL,
        ifUnchangedFrom expectedContents: String
    ) -> CoordinatedGuardedSaveOutcome {
        switch diskState(at: url, expectedContents: expectedContents) {
        case .saved:
            do {
                try fileAccess.write(text, to: url)
                return .saved
            } catch {
                return .failed(error.localizedDescription)
            }
        case .changedOnDisk(let externalContents):
            return .changedOnDisk(externalContents)
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message)
        }
    }
}

nonisolated final class CoordinatedFileAccess {
    static func placeUbiquitousItem(
        data: Data,
        at destinationURL: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileAccess().placeUbiquitousItem(
                data: data,
                at: destinationURL
            )
        }.value
    }

    static func downloadAndVerifyUbiquitousItem(at url: URL) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        try await verifyReadable(at: url)
    }

    static func verifyReadable(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            _ = try CoordinatedFileAccess().data(at: url)
        }.value
    }

    func read<T>(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions = [],
        _ accessor: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?

        coordinator.coordinate(
            readingItemAt: url,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try accessor(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }

    func write<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        _ accessor: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?

        coordinator.coordinate(
            writingItemAt: url,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try accessor(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try result.get()
    }

    func createDirectory(at url: URL) throws {
        try write(at: url, options: .forReplacing) { coordinatedURL in
            try FileManager.default.createDirectory(
                at: coordinatedURL,
                withIntermediateDirectories: true
            )
        }
    }

    func string(at url: URL) throws -> String {
        try read(at: url) { coordinatedURL in
            try String(contentsOf: coordinatedURL, encoding: .utf8)
        }
    }

    func data(at url: URL) throws -> Data {
        try read(at: url) { coordinatedURL in
            try Data(contentsOf: coordinatedURL)
        }
    }

    func write(_ text: String, to url: URL) throws {
        try write(at: url, options: .forReplacing) { coordinatedURL in
            try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
        }
    }

    func write(_ data: Data, to url: URL) throws {
        try write(at: url, options: .forReplacing) { coordinatedURL in
            try data.write(to: coordinatedURL, options: .atomic)
        }
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]
    ) throws -> [URL] {
        try read(at: url) { coordinatedURL in
            try FileManager.default.contentsOfDirectory(
                at: coordinatedURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        }
    }

    func itemExists(at url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        return (try? read(at: parent) { _ in
            FileManager.default.fileExists(atPath: url.path)
        }) ?? false
    }

    func regularFilesRecursively(at url: URL) throws -> [URL] {
        try read(at: url) { coordinatedURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                return []
            }

            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
            guard let enumerator = FileManager.default.enumerator(
                at: coordinatedURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return enumerator.compactMap { item in
                guard let itemURL = item as? URL,
                      let values = try? itemURL.resourceValues(
                        forKeys: Set(keys)
                      ),
                      values.isRegularFile == true else {
                    return nil
                }
                return itemURL
            }
        }
    }

    func directoriesRecursively(at url: URL) throws -> [URL] {
        try read(at: url) { coordinatedURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                return []
            }
            let keys: [URLResourceKey] = [.isDirectoryKey]
            guard let enumerator = FileManager.default.enumerator(
                at: coordinatedURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return enumerator.compactMap { item in
                guard let itemURL = item as? URL,
                      let values = try? itemURL.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true else { return nil }
                return itemURL
            }
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try coordinateMoveOrCopy(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            sourceOptions: .forMoving
        ) { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try coordinateMoveOrCopy(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            sourceOptions: []
        ) { source, destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func removeItem(at url: URL) throws {
        try write(at: url, options: .forDeleting) { coordinatedURL in
            try FileManager.default.removeItem(at: coordinatedURL)
        }
    }

    /// Creates a complete local file first, then asks Foundation to register
    /// and move it into the iCloud Documents container. Apple recommends this
    /// path for shipping apps because a successful local write alone does not
    /// prove that a new item has entered the iCloud upload workflow.
    func placeUbiquitousItem(
        data: Data,
        at destinationURL: URL
    ) throws {
        let fileManager = FileManager.default
        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "ghostWriter-iCloud-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        let stagedURL = stagingDirectory.appendingPathComponent(
            destinationURL.lastPathComponent
        )
        try data.write(to: stagedURL, options: .atomic)
        try fileManager.setUbiquitous(
            true,
            itemAt: stagedURL,
            destinationURL: destinationURL
        )
    }

    private func coordinateMoveOrCopy(
        sourceURL: URL,
        destinationURL: URL,
        sourceOptions: NSFileCoordinator.WritingOptions,
        operation: (URL, URL) throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?

        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: sourceOptions,
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { source, destination in
            do {
                try operation(source, destination)
            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let operationError {
            throw operationError
        }
    }
}
