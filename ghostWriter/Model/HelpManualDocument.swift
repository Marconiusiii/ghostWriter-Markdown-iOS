import Foundation

/// The bundle supplies the initial text; explicit saves belong to the library file.
enum HelpManualDocument {
    static let name = "ghostWriter Help Manual"
    static var bundledURL: URL? {
        Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: name, withExtension: "md")
    }
    static func libraryURL(in root: URL) -> URL { root.appendingPathComponent(name + ".md") }
    static func isManual(_ candidate: URL?) -> Bool { candidate?.lastPathComponent == name + ".md" }

    private static var installations: [URL: Task<URL, Error>] = [:]

    static func installIfNeeded(in store: DocumentStore) async throws -> URL {
        let root = store.directory
        let target = libraryURL(in: root)
        if let task = installations[root] { return try await task.value }
        let task = Task<URL, Error> {
            if store.documents.contains(where: { $0.url.standardizedFileURL == target.standardizedFileURL })
                || FileManager.default.fileExists(atPath: target.path) { return target }
            guard let bundledURL else { throw WordThemeError.invalid("The bundled ghostWriter Help Manual could not be found.") }
            let markdown = try String(contentsOf: bundledURL, encoding: .utf8)
            guard let created = await store.createDocument(named: name, contents: markdown, in: root) else {
                throw WordThemeError.invalid(store.lastError ?? "The ghostWriter Help Manual could not be installed.")
            }
            return created
        }
        installations[root] = task
        defer { installations[root] = nil }
        return try await task.value
    }
}

