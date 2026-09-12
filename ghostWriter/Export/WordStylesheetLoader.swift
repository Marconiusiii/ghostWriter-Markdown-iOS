import Foundation

nonisolated enum WordStylesheetLoader {
    static let folderName = "Word Stylesheets"
    static func directory(in root: URL) -> URL { root.appendingPathComponent(folderName, isDirectory: true) }
    static func contains(_ url: URL, in root: URL) -> Bool {
        let folder = directory(in: root).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == folder || path.hasPrefix(folder + "/")
    }
    static func loadSelection(_ filename: String, in root: URL) async throws -> WordExportTheme? {
        guard !filename.isEmpty else { return nil }
        do {
            guard let theme = try await WordStylesheetLoader.load(in: root, enabled: true, filename: filename) else {
                throw WordThemeError.invalid("The file is no longer available. Choose another stylesheet or Standard Word output.")
            }
            return theme
        } catch is CancellationError { throw CancellationError() }
        catch { throw WordThemeError.invalid("\(filename): \(error.localizedDescription)") }
    }

    static let filename = "word-theme.json"

    struct Choice: Identifiable, Equatable, Sendable {
        var filename: String
        var error: String?
        var id: String { filename }
        var name: String { String(filename.dropLast(5)) }
    }

    static func choices(in root: URL) async throws -> [Choice] {
        let folder = directory(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sample = folder.appendingPathComponent("Large Print.json")
        // Install the optional example once per library; respect subsequent deletion.
        let marker = folder.appendingPathComponent(".large-print-installed")
        if !FileManager.default.fileExists(atPath: marker.path) {
            if !FileManager.default.fileExists(atPath: sample.path) {
                try Data(largePrint.utf8).write(to: sample, options: .withoutOverwriting)
            }
            try Data().write(to: marker, options: .atomic)
        }
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var result: [Choice] = []
        for url in urls {
            try Task.checkCancellation()
            do {
                guard try await load(in: root, enabled: true, filename: url.lastPathComponent) != nil else {
                    throw WordThemeError.invalid("The stylesheet is no longer available.")
                }
                result.append(Choice(filename: url.lastPathComponent))
            } catch is CancellationError { throw CancellationError() }
            catch { result.append(Choice(filename: url.lastPathComponent, error: error.localizedDescription)) }
        }
        return result
    }

    static let largePrint = """
    {
      "version": 1,
      "body": { "font": "Arial", "size": 18, "lineSpacing": 1.5, "spaceAfter": 12 },
      "headings": {
        "1": { "size": 28, "keepWithNext": true },
        "2": { "size": 24, "keepWithNext": true },
        "3": { "size": 22, "keepWithNext": true },
        "4": { "size": 20, "keepWithNext": true },
        "5": { "size": 18, "keepWithNext": true },
        "6": { "size": 18, "keepWithNext": true }
      }
    }
    """

    static func load(in root: URL, enabled: Bool, filename: String = filename) async throws -> WordExportTheme? {
        guard enabled else { return nil }
        try Task.checkCancellation()
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.lowercased().hasSuffix(".json") else { throw WordThemeError.invalid("Choose a JSON file in Word Stylesheets.") }
        let folder = directory(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            let deadline = Date().addingTimeInterval(30)
            while true {
                try Task.checkCancellation()
                var refreshedURL = url
                refreshedURL.removeAllCachedResourceValues()
                let status = try refreshedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
                if status == .current || status == .downloaded { break }
                guard Date() < deadline else { throw WordThemeError.invalid("\(filename) is not downloaded yet. Try again when it is available in Files.") }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        try Task.checkCancellation()
        do { return try WordExportTheme.load(from: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }
}
