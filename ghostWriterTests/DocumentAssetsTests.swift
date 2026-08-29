import Foundation
import Testing
@testable import ghostWriter

struct DocumentAssetsTests {
    @Test func photoLibraryPNGIsKeptInASupportedFormat() throws {
        let prepared = try DocumentAssets.preparePhotoAsset(data: tinyPNG)

        #expect(prepared.data == tinyPNG)
        #expect(prepared.fileName == "photo.png")
    }

    @Test func otherDecodablePhotoLibraryFormatsBecomeJPEG() throws {
        let prepared = try DocumentAssets.preparePhotoAsset(data: tinyGIF)

        #expect(prepared.fileName == "photo.jpg")
        #expect(ExportImageResource.hasValidImageData(prepared.data, mediaType: "image/jpeg"))
    }

    @Test func unreadablePhotoLibraryDataIsRejected() {
        #expect(throws: (any Error).self) {
            try DocumentAssets.preparePhotoAsset(data: Data("not an image".utf8))
        }
    }

    @Test func importedTactileAssetUsesAManagedRelativeReference() throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Document.md")
        let access = CoordinatedFileAccess()

        let reference = try DocumentAssets.importAsset(
            data: Data([1, 2, 3]),
            originalFileName: "Raised map.svg",
            beside: document,
            fileAccess: access
        )

        #expect(reference.hasPrefix(".ghostwriter-assets-"))
        #expect(reference.hasSuffix("/Raised_map.svg"))
        #expect(access.itemExists(at: root.appendingPathComponent(reference)))
    }

    @Test func importedAssetsMoveWithTheirDocument() throws {
        let root = temporaryDirectory()
        let sourceFolder = root.appendingPathComponent("Source", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceFolder.appendingPathComponent("Document.md")
        let destination = destinationFolder.appendingPathComponent("Document.md")
        let name = ".ghostwriter-assets-11111111-1111-1111-1111-111111111111"
        let imported = WordMarkdownImport(
            markdown: "![Description](\(name)/image.png)",
            assets: [WordImportedAsset(fileName: "image.png", data: Data([1, 2, 3]))],
            imagesNeedingAlternativeText: 0,
            assetDirectoryName: name
        )
        let access = CoordinatedFileAccess()
        try DocumentAssets.write(imported, to: source, fileAccess: access)
        try access.moveItem(at: source, to: destination)
        try DocumentAssets.moveAfterDocumentMove(
            from: source,
            to: destination,
            fileAccess: access
        )

        #expect(!access.itemExists(at: DocumentAssets.directory(named: name, beside: source)))
        #expect(access.itemExists(at: DocumentAssets.directory(named: name, beside: destination)))
        #expect(try access.string(at: destination) == imported.markdown)
    }

    @Test func duplicatedDocumentReceivesIndependentAssetDirectory() throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Original.md")
        let destination = root.appendingPathComponent("Copy.md")
        let name = ".ghostwriter-assets-22222222-2222-2222-2222-222222222222"
        let access = CoordinatedFileAccess()
        try DocumentAssets.write(
            WordMarkdownImport(
                markdown: "![](\(name)/decoration.png)",
                assets: [WordImportedAsset(fileName: "decoration.png", data: Data([4, 5, 6]))],
                imagesNeedingAlternativeText: 0,
                assetDirectoryName: name
            ),
            to: source,
            fileAccess: access
        )
        try access.copyItem(at: source, to: destination)
        try DocumentAssets.copyAfterDocumentCopy(
            from: source,
            to: destination,
            fileAccess: access
        )

        let copiedMarkdown = try access.string(at: destination)
        let copiedName = try #require(DocumentAssets.directoryNames(in: copiedMarkdown).first)
        #expect(copiedName != name)
        #expect(access.itemExists(at: DocumentAssets.directory(named: name, beside: source)))
        #expect(access.itemExists(at: DocumentAssets.directory(named: copiedName, beside: destination)))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "ghostWriterDocumentAssets-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private var tinyPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) ?? Data()
    }

    private var tinyGIF: Data {
        Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==") ?? Data()
    }
}
