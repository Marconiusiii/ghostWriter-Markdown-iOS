import Foundation

nonisolated enum DocumentAssets {
    private static let directoryPrefix = ".ghostwriter-assets-"

    static func newDirectoryName() -> String {
        directoryPrefix + UUID().uuidString.lowercased()
    }

    /// Stores a user-selected resource beside the document and returns the
    /// relative path written into Markdown. Using the same managed-directory
    /// convention as Word import means rename, duplicate, iCloud download, and
    /// deletion already carry the attachment with its document.
    static func importAsset(
        data: Data,
        originalFileName: String,
        beside documentURL: URL,
        fileAccess: CoordinatedFileAccess = CoordinatedFileAccess()
    ) throws -> String {
        guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }

        let directoryName = newDirectoryName()
        let assetDirectory = directory(named: directoryName, beside: documentURL)
        let fileName = safeFileName(originalFileName)

        do {
            try fileAccess.createDirectory(at: assetDirectory)
            try fileAccess.write(data, to: assetDirectory.appendingPathComponent(fileName))
            return "\(directoryName)/\(fileName)"
        } catch {
            if fileAccess.itemExists(at: assetDirectory) {
                try? fileAccess.removeItem(at: assetDirectory)
            }
            throw error
        }
    }

    private static func safeFileName(_ original: String) -> String {
        let name = URL(fileURLWithPath: original).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        let cleaned = String(name.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        })
        return cleaned.isEmpty ? "graphic" : cleaned
    }

    static func directory(
        named name: String,
        beside documentURL: URL
    ) -> URL {
        documentURL.deletingLastPathComponent().appendingPathComponent(
            name,
            isDirectory: true
        )
    }

    static func write(
        _ imported: WordMarkdownImport,
        to documentURL: URL,
        fileAccess: CoordinatedFileAccess
    ) throws {
        let assetDirectory = imported.assetDirectoryName.map {
            directory(named: $0, beside: documentURL)
        }
        do {
            if let assetDirectory, !imported.assets.isEmpty {
                try fileAccess.createDirectory(at: assetDirectory)
                for asset in imported.assets {
                    try fileAccess.write(
                        asset.data,
                        to: assetDirectory.appendingPathComponent(asset.fileName)
                    )
                }
            }
            try fileAccess.write(imported.markdown, to: documentURL)
        } catch {
            if let assetDirectory, fileAccess.itemExists(at: assetDirectory) {
                try? fileAccess.removeItem(at: assetDirectory)
            }
            throw error
        }
    }

    static func moveAfterDocumentMove(
        from sourceURL: URL,
        to destinationURL: URL,
        fileAccess: CoordinatedFileAccess
    ) throws {
        let markdown = try fileAccess.string(at: destinationURL)
        var movedNames: [String] = []
        do {
            for name in directoryNames(in: markdown) {
                let source = directory(named: name, beside: sourceURL)
                guard fileAccess.itemExists(at: source) else { continue }
                let destination = directory(named: name, beside: destinationURL)
                if source.standardizedFileURL == destination.standardizedFileURL {
                    continue
                }
                try fileAccess.moveItem(at: source, to: destination)
                movedNames.append(name)
            }
        } catch {
            for name in movedNames.reversed() {
                try? fileAccess.moveItem(
                    at: directory(named: name, beside: destinationURL),
                    to: directory(named: name, beside: sourceURL)
                )
            }
            throw error
        }
    }

    static func copyAfterDocumentCopy(
        from sourceURL: URL,
        to destinationURL: URL,
        fileAccess: CoordinatedFileAccess
    ) throws {
        var markdown = try fileAccess.string(at: destinationURL)
        let originalNames = directoryNames(in: markdown)
        var copiedDirectories: [URL] = []
        do {
            for originalName in originalNames {
                let source = directory(named: originalName, beside: sourceURL)
                guard fileAccess.itemExists(at: source) else { continue }
                let newName = newDirectoryName()
                let destination = directory(named: newName, beside: destinationURL)
                try fileAccess.copyItem(at: source, to: destination)
                copiedDirectories.append(destination)
                markdown = rewriteReferences(
                    in: markdown,
                    from: originalName,
                    to: newName
                )
            }
            try fileAccess.write(markdown, to: destinationURL)
        } catch {
            for directory in copiedDirectories {
                try? fileAccess.removeItem(at: directory)
            }
            throw error
        }
    }

    static func duplicateIntoICloud(
        from sourceURL: URL,
        to destinationURL: URL,
        fileAccess: CoordinatedFileAccess,
        placeItem: (Data, URL) async throws -> Void
    ) async throws {
        var markdown = try fileAccess.string(at: sourceURL)
        var placements: [(data: Data, relativePath: String)] = []
        var directoryNamesToCreate: [String] = []
        for originalName in directoryNames(in: markdown) {
            let sourceDirectory = directory(named: originalName, beside: sourceURL)
            guard fileAccess.itemExists(at: sourceDirectory) else { continue }
            let newName = newDirectoryName()
            directoryNamesToCreate.append(newName)
            let files = try fileAccess.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            for file in files where
                (try? file.resourceValues(forKeys: [.isRegularFileKey]))?
                    .isRegularFile == true {
                placements.append((
                    try fileAccess.data(at: file),
                    newName + "/" + file.lastPathComponent
                ))
            }
            markdown = rewriteReferences(
                in: markdown,
                from: originalName,
                to: newName
            )
        }

        var createdDirectories: [URL] = []
        do {
            for name in directoryNamesToCreate {
                let assetDirectory = directory(named: name, beside: destinationURL)
                try fileAccess.createDirectory(at: assetDirectory)
                createdDirectories.append(assetDirectory)
            }
            for placement in placements {
                try await placeItem(
                    placement.data,
                    destinationURL.deletingLastPathComponent()
                        .appendingPathComponent(placement.relativePath)
                )
            }
            try await placeItem(Data(markdown.utf8), destinationURL)
        } catch {
            for directory in createdDirectories {
                try? fileAccess.removeItem(at: directory)
            }
            if fileAccess.itemExists(at: destinationURL) {
                try? fileAccess.removeItem(at: destinationURL)
            }
            throw error
        }
    }

    static func directories(
        for documentURL: URL,
        fileAccess: CoordinatedFileAccess
    ) throws -> [URL] {
        let markdown = try fileAccess.string(at: documentURL)
        return directoryNames(in: markdown).map {
            directory(named: $0, beside: documentURL)
        }.filter { fileAccess.itemExists(at: $0) }
    }

    static func files(
        referencedBy markdown: String,
        beside documentURL: URL,
        fileAccess: CoordinatedFileAccess
    ) throws -> [URL] {
        var result: [URL] = []
        for name in directoryNames(in: markdown) {
            let assetDirectory = directory(named: name, beside: documentURL)
            guard fileAccess.itemExists(at: assetDirectory) else { continue }
            result += try fileAccess.contentsOfDirectory(
                at: assetDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey
                ]
            ).filter { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
                    return false
                }
                return values.isRegularFile == true
            }
        }
        return result
    }

    static func directoryNames(in markdown: String) -> [String] {
        let pattern = #"\.ghostwriter-assets-[a-fA-F0-9-]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(markdown.startIndex..., in: markdown)
        var names: [String] = []
        for match in expression.matches(in: markdown, range: range) {
            guard let swiftRange = Range(match.range, in: markdown) else { continue }
            let name = String(markdown[swiftRange])
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func rewriteReferences(
        in markdown: String,
        from oldName: String,
        to newName: String
    ) -> String {
        markdown
            .replacingOccurrences(of: oldName + "/", with: newName + "/")
            .replacingOccurrences(
                of: encodedPathComponent(oldName) + "/",
                with: encodedPathComponent(newName) + "/"
            )
    }

    private static func encodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
