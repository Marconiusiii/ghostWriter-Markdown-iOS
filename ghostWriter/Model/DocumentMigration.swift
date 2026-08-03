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
    private struct MigrationOperation {
        let pair: DocumentMigrationPair
        let createdDestination: Bool
    }

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
        destinationUsesICloud: Bool = false,
        reusableSourceTemplates: [String: Data] = [:]
    ) throws
        -> DocumentMigrationResult {
        guard sourceDirectory.standardizedFileURL
            != destinationDirectory.standardizedFileURL else {
            throw DocumentMigrationError.sameLocation
        }

        try fileAccess.createDirectory(at: destinationDirectory)
        let sourceFiles = try fileAccess.regularFilesRecursively(
            at: sourceDirectory
        ).sorted {
            $0.standardizedFileURL.path
                .localizedStandardCompare($1.standardizedFileURL.path)
                == .orderedAscending
        }
        var operations: [MigrationOperation] = []

        do {
            for sourceURL in sourceFiles {
                let relativePath = relativePath(
                    of: sourceURL,
                    beneath: sourceDirectory
                )
                let proposedDestination = destinationDirectory
                    .appendingPathComponent(relativePath)
                let sourceData = try fileAccess.data(at: sourceURL)

                // A bundled starter document is replaceable only while its
                // source bytes are still pristine. Reusing an existing
                // destination prevents reinstall migrations from creating a
                // numbered Welcome duplicate while preserving any edits that
                // already exist in iCloud.
                if reusableSourceTemplates[relativePath] == sourceData,
                   isRegularFile(at: proposedDestination) {
                    operations.append(
                        MigrationOperation(
                            pair: DocumentMigrationPair(
                                sourceURL: sourceURL,
                                destinationURL: proposedDestination
                            ),
                            createdDestination: false
                        )
                    )
                    continue
                }

                let destinationURL = availableURL(for: proposedDestination)

                try fileAccess.createDirectory(
                    at: destinationURL.deletingLastPathComponent()
                )
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

                operations.append(
                    MigrationOperation(
                        pair: DocumentMigrationPair(
                            sourceURL: sourceURL,
                            destinationURL: destinationURL
                        ),
                        createdDestination: true
                    )
                )
            }
        } catch {
            for operation in operations.reversed()
            where operation.createdDestination {
                try? fileAccess.removeItem(
                    at: operation.pair.destinationURL
                )
            }
            throw error
        }

        var cleanupFailures: [URL] = []
        for operation in operations {
            do {
                try fileAccess.removeItem(at: operation.pair.sourceURL)
            } catch {
                cleanupFailures.append(operation.pair.sourceURL)
            }
        }

        return DocumentMigrationResult(
            migrated: operations.map(\.pair),
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

    private func isRegularFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
    }
}
