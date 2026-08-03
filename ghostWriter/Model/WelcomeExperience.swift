//
//  WelcomeExperience.swift
//  ghostWriter
//
//  Installs the editable welcome guide once and remembers when the user has
//  deliberately completed the first-launch introduction.
//

import Foundation
import Observation

enum WelcomeDocument {
    static let name = "Welcome to ghostWriter Markdown"
    static let fileName = "\(name).md"

    static func bundledMarkdown(in bundle: Bundle = .main) throws -> String {
        let resourceURL = bundle.url(
            forResource: name,
            withExtension: "md",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: name, withExtension: "md")

        guard let resourceURL else {
            throw WelcomeDocumentError.missingResource
        }
        return try String(contentsOf: resourceURL, encoding: .utf8)
    }
}

enum WelcomeDocumentError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        "The bundled Welcome document could not be found."
    }
}

@Observable
final class WelcomeExperience {
    private(set) var hasCompleted: Bool
    private(set) var hasInstalledDocument: Bool

    var shouldPresent: Bool { !hasCompleted }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompleted = defaults.bool(forKey: Keys.completed)
        self.hasInstalledDocument = defaults.bool(
            forKey: Keys.documentInstalled
        )
    }

    func complete() {
        hasCompleted = true
        defaults.set(true, forKey: Keys.completed)
    }

    /// Returns the existing guide or installs a fresh copy. Once installation
    /// succeeds, deleting the guide is respected and does not recreate it.
    func installDocumentIfNeeded(
        in store: DocumentStore,
        markdown: @autoclosure () throws -> String
    ) async -> URL? {
        let existingURL = store.documents.first {
            $0.fileName.caseInsensitiveCompare(WelcomeDocument.fileName)
                == .orderedSame
        }?.url

        if let existingURL {
            markDocumentInstalled()
            return existingURL
        }

        guard !hasInstalledDocument else { return nil }

        do {
            guard let url = await store.createDocument(
                named: WelcomeDocument.name,
                contents: try markdown()
            ) else {
                return nil
            }
            markDocumentInstalled()
            store.refresh()
            return url
        } catch {
            store.lastError = error.localizedDescription
            return nil
        }
    }

    private func markDocumentInstalled() {
        hasInstalledDocument = true
        defaults.set(true, forKey: Keys.documentInstalled)
    }

    private enum Keys {
        static let completed = "welcomeExperienceCompleted"
        static let documentInstalled = "welcomeDocumentInstalled"
    }
}
