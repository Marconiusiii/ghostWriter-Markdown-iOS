//
//  WelcomeExperienceTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct WelcomeExperienceTests {

    @Test func firstLaunchPresentationPersistsOnlyAfterCompletion() {
        let testDefaults = makeDefaults()
        defer { cleanUp(testDefaults) }

        let experience = WelcomeExperience(defaults: testDefaults.defaults)
        #expect(experience.shouldPresent)

        experience.complete()

        let restored = WelcomeExperience(defaults: testDefaults.defaults)
        #expect(!restored.shouldPresent)
    }

    @Test func bundledGuideContainsTheSupportedMarkdownTopics() throws {
        let markdown = try WelcomeDocument.bundledMarkdown()

        #expect(markdown.contains("# Welcome to ghostWriter Markdown"))
        #expect(markdown.contains("## Organize with Headings"))
        #expect(markdown.contains("## Make Lists"))
        #expect(markdown.contains("## Create Links and Images"))
        #expect(markdown.contains("## Build a Table"))
        #expect(markdown.contains("## Your Documents and iCloud"))
    }

    @Test func guideIsInstalledWithoutChangingItsMarkdown() async throws {
        let testDefaults = makeDefaults()
        let directory = temporaryDirectory()
        defer {
            cleanUp(testDefaults)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = DocumentStore(directory: directory)
        let experience = WelcomeExperience(defaults: testDefaults.defaults)
        let markdown = "# Welcome\n\nA small guide."

        let url = await experience.installDocumentIfNeeded(
            in: store,
            markdown: markdown
        )

        #expect(url?.lastPathComponent == WelcomeDocument.fileName)
        #expect(url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } == markdown)
        #expect(experience.hasInstalledDocument)
    }

    @Test func existingWelcomeDocumentIsNeverOverwritten() async throws {
        let testDefaults = makeDefaults()
        let directory = temporaryDirectory()
        defer {
            cleanUp(testDefaults)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = DocumentStore(directory: directory)
        let existingText = "My existing document"
        let existingURL = try #require(
            store.createDocument(
                named: WelcomeDocument.name,
                contents: existingText
            )
        )
        store.refresh()
        let experience = WelcomeExperience(defaults: testDefaults.defaults)

        let returnedURL = await experience.installDocumentIfNeeded(
            in: store,
            markdown: "Replacement text"
        )

        #expect(returnedURL == existingURL)
        #expect(try String(contentsOf: existingURL, encoding: .utf8) == existingText)
    }

    @Test func deletedGuideIsNotRecreatedAfterSuccessfulInstallation() async throws {
        let testDefaults = makeDefaults()
        let directory = temporaryDirectory()
        defer {
            cleanUp(testDefaults)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = DocumentStore(directory: directory)
        let experience = WelcomeExperience(defaults: testDefaults.defaults)
        let installedURL = try #require(
            await experience.installDocumentIfNeeded(
                in: store,
                markdown: "# Welcome"
            )
        )
        try FileManager.default.removeItem(at: installedURL)
        store.refresh()

        let recreatedURL = await experience.installDocumentIfNeeded(
            in: store,
            markdown: "# Welcome again"
        )

        #expect(recreatedURL == nil)
        #expect(!FileManager.default.fileExists(atPath: installedURL.path))
    }

    @Test func failedInstallationCanBeRetriedLater() async {
        let testDefaults = makeDefaults()
        let directory = temporaryDirectory()
        defer {
            cleanUp(testDefaults)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = DocumentStore(
            directory: directory,
            storageAvailable: false
        )
        let experience = WelcomeExperience(defaults: testDefaults.defaults)

        let firstURL = await experience.installDocumentIfNeeded(
            in: store,
            markdown: "# Welcome"
        )
        #expect(firstURL == nil)
        #expect(!experience.hasInstalledDocument)

        store.useDirectory(directory)
        let retryURL = await experience.installDocumentIfNeeded(
            in: store,
            markdown: "# Welcome"
        )
        #expect(retryURL != nil)
        #expect(experience.hasInstalledDocument)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WelcomeExperienceTests-\(UUID().uuidString)")
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "WelcomeExperienceTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanUp(
        _ testDefaults: (defaults: UserDefaults, suiteName: String)
    ) {
        testDefaults.defaults.removePersistentDomain(
            forName: testDefaults.suiteName
        )
    }
}
