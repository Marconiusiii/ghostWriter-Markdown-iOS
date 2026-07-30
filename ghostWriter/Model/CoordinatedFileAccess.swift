//
//  CoordinatedFileAccess.swift
//  ghostWriter
//
//  All document operations pass through NSFileCoordinator. This is required
//  for iCloud documents and also coordinates with Files and other presenters
//  when the user keeps the library locally.
//

import Foundation

nonisolated final class CoordinatedFileAccess {
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
