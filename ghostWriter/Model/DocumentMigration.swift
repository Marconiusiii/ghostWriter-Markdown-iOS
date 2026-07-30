//
//  DocumentMigration.swift
//  ghostWriter
//
//  Copies and verifies a complete library before removing any source files.
//  A failed copy rolls back everything created during that attempt, leaving the
//  active library unchanged.
//

import Foundation

nonisolated struct DocumentMigrationPair: Equatable, Sendable {
    let sourceURL: URL
    let destinationURL: URL
}

nonisolated struct DocumentMigrationResult: Equatable, Sendable {
    let migrated: [DocumentMigrationPair]
    let cleanupFailures: [URL]
}

nonisolated enum DocumentMigrationError: LocalizedError {
    case sameLocation
    case couldNotVerify(String)

    var errorDescription: String? {
        switch self {
        case .sameLocation:
            return "The source and destination libraries are the same."
        case .couldNotVerify(let fileName):
            return "ghostWriter could not verify \(fileName) after copying it."
        }
    }
}

nonisolated final class DocumentMigration {
    private let fileAccess: CoordinatedFileAccess
    private let fileManager: FileManager
    private let placeUbiquitousItem: (Data, URL) throws -> Void

    init(
        fileAccess: CoordinatedFileAccess = CoordinatedFileAccess(),
        fileManager: FileManager = .default,
        placeUbiquitousItem:
            ((Data, URL) throws -> Void)? = nil
    ) {
        self.fileAccess = fileAccess
        self.fileManager = fileManager
        self.placeUbiquitousItem = placeUbiquitousItem ?? {
            try fileAccess.placeUbiquitousItem(data: $0, at: $1)
        }
    }

    func migrate(
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        destinationUsesICloud: Bool = false
    ) throws
        -> DocumentMigrationResult {
        guard sourceDirectory.standardizedFileURL
            != destinationDirectory.standardizedFileURL else {
            throw DocumentMigrationError.sameLocation
        }

        try fileAccess.createDirectory(at: destinationDirectory)
        let sourceFiles = try fileAccess.regularFilesRecursively(
            at: sourceDirectory
        )
        var copiedPairs: [DocumentMigrationPair] = []

        do {
            for sourceURL in sourceFiles {
                let relativePath = relativePath(
                    of: sourceURL,
                    beneath: sourceDirectory
                )
                let proposedDestination = destinationDirectory
                    .appendingPathComponent(relativePath)
                let destinationURL = availableURL(for: proposedDestination)

                try fileAccess.createDirectory(
                    at: destinationURL.deletingLastPathComponent()
                )
                let sourceData = try fileAccess.data(at: sourceURL)
                if destinationUsesICloud {
                    try placeUbiquitousItem(
                        sourceData,
                        destinationURL
                    )
                } else {
                    try fileAccess.copyItem(
                        at: sourceURL,
                        to: destinationURL
                    )
                }

                guard sourceData
                    == (try fileAccess.data(at: destinationURL)) else {
                    throw DocumentMigrationError.couldNotVerify(
                        sourceURL.lastPathComponent
                    )
                }

                copiedPairs.append(
                    DocumentMigrationPair(
                        sourceURL: sourceURL,
                        destinationURL: destinationURL
                    )
                )
            }
        } catch {
            for pair in copiedPairs.reversed() {
                try? fileAccess.removeItem(at: pair.destinationURL)
            }
            throw error
        }

        var cleanupFailures: [URL] = []
        for pair in copiedPairs {
            do {
                try fileAccess.removeItem(at: pair.sourceURL)
            } catch {
                cleanupFailures.append(pair.sourceURL)
            }
        }

        return DocumentMigrationResult(
            migrated: copiedPairs,
            cleanupFailures: cleanupFailures
        )
    }

    private func relativePath(of fileURL: URL, beneath directoryURL: URL) -> String {
        let rootPath = directoryURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(prefix.count))
    }

    private func availableURL(for proposedURL: URL) -> URL {
        guard fileManager.fileExists(atPath: proposedURL.path) else {
            return proposedURL
        }

        let directory = proposedURL.deletingLastPathComponent()
        let pathExtension = proposedURL.pathExtension
        let baseName = proposedURL.deletingPathExtension().lastPathComponent
        var counter = 2

        while true {
            var candidate = directory.appendingPathComponent(
                "\(baseName) \(counter)"
            )
            if !pathExtension.isEmpty {
                candidate.appendPathExtension(pathExtension)
            }
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
