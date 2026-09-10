import Foundation

nonisolated enum WordStylesheetLoader {
    static let folderName = "Word Stylesheets"
    static func directory(in root: URL) -> URL { root.appendingPathComponent(folderName, isDirectory: true) }
    static func contains(_ url: URL, in root: URL) -> Bool {
        let folder = directory(in: root).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == folder || path.hasPrefix(folder + "/")
    }
    static let filename = "word-theme.json"

    static func load(in root: URL, enabled: Bool) async throws -> WordExportTheme? {
        guard enabled else { return nil }
        try Task.checkCancellation()
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
                guard Date() < deadline else { throw WordThemeError.invalid("word-theme.json is not downloaded yet. Try again when it is available in Files.") }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        try Task.checkCancellation()
        do { return try WordExportTheme.load(from: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }
}
