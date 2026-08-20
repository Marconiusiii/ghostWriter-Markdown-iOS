//
//  EBrailleWriterTests.swift
//  ghostWriterTests
//
//  Covers eBraille conformance: the things that make a publication valid rather
//  than merely well-formed.
//
//  The package is a zip, so these tests unpack it and read the parts. Several
//  of the requirements checked here — the root file names, the mandatory
//  metadata, the Brai subtag — fail silently: the file opens, looks plausible,
//  and is rejected by a conforming reading system.
//

import Foundation
import Testing
import ZIPFoundation
@testable import ghostWriter

struct EBrailleWriterTests {

    /// Stands in for liblouis so these tests exercise packaging rather than
    /// translation. Braille here is a marker, not real UEB: what matters is
    /// that translated text reaches the output and print text does not.
    private struct StubTranslator: BrailleTranslator {
        func translate(
            _ input: BrailleTranslationInput,
            grade: BrailleGrade
        ) async throws -> String {
            // A recognisable braille pattern per input character.
            String(repeating: "\u{2801}", count: max(input.text.count, 1))
        }
    }

    private func makePackage(
        title: String = "Test Document",
        markdown: String,
        sourceDirectory: URL? = nil,
        metadata: EBrailleMetadata = EBrailleMetadata(
            creator: "A Writer",
            transcriber: "Test Transcriber",
            grade: .grade2,
            copyrightYear: "2026"
        )
    ) async throws -> [String: String] {
        let data = try await EBrailleWriter.write(
            title: title,
            markdown: markdown,
            metadata: metadata,
            translator: StubTranslator(),
            sourceDirectory: sourceDirectory
        )

        let archive = try Archive(data: data, accessMode: .read)
        var entries: [String: String] = [:]
        for entry in archive {
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            entries[entry.path] = String(decoding: bytes, as: UTF8.self)
        }
        return entries
    }

    @Test func packageUsesTheRequiredRootFileNames() async throws {
        let entries = try await makePackage(markdown: "# Heading\n\nText.")

        // eBraille fixes both names and locations. EPUB's own conventions —
        // OEBPS/content.opf and nav.xhtml — are non-conforming here.
        #expect(entries["package.opf"] != nil)
        #expect(entries["index.html"] != nil)
        #expect(entries["OEBPS/content.opf"] == nil)
    }

    @Test func mimetypeIsPresentAndCorrect() async throws {
        let entries = try await makePackage(markdown: "Text.")

        #expect(entries["mimetype"] == "application/epub+zip")
    }

    @Test func packageDeclaresEveryRequiredProperty() async throws {
        let entries = try await makePackage(markdown: "Text.")
        let package = try #require(entries["package.opf"])

        // Each of these is mandatory. A file missing any one of them is not
        // conforming, however well-formed the rest is.
        #expect(package.contains("<dc:format>eBraille 1.0</dc:format>"))
        #expect(package.contains("a11y:brailleCellType"))
        #expect(package.contains("a11y:brailleSystem"))
        #expect(package.contains("a11y:completeTranscription"))
        #expect(package.contains("a11y:tactileGraphics"))
        #expect(package.contains("a11y:producer"))
        #expect(package.contains("dcterms:dateCopyrighted"))
        #expect(package.contains("<dc:creator>A Writer</dc:creator>"))
        #expect(package.contains("<dc:title xml:lang=\"en\">Test Document</dc:title>"))
    }

    @Test func brailleSystemMatchesTheChosenGrade() async throws {
        let grade1 = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(creator: "A Writer", transcriber: "Test Transcriber", grade: .grade1, copyrightYear: "2026")
        )
        let grade2 = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(creator: "A Writer", transcriber: "Test Transcriber", grade: .grade2, copyrightYear: "2026")
        )

        #expect(try #require(grade1["package.opf"]).contains("ueb grade1"))
        #expect(try #require(grade2["package.opf"]).contains("ueb grade2"))
    }

    @Test func producerNamesTheResponsibleTranscriber() async throws {
        let entries = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(creator: "Someone Else", transcriber: "Braille Services", grade: .grade2, copyrightYear: "2026")
        )
        let package = try #require(entries["package.opf"])

        #expect(package.contains("<meta property=\"a11y:producer\">Braille Services</meta>"))
        #expect(!package.contains("<meta property=\"a11y:producer\">ghostWriter Markdown</meta>"))
    }

    @Test func languageCarriesTheBrailleScriptSubtag() async throws {
        let entries = try await makePackage(markdown: "Text.")
        let package = try #require(entries["package.opf"])

        #expect(package.contains("<dc:language>en-Brai</dc:language>"))
    }

    @Test func contentContainsBrailleRatherThanPrint() async throws {
        let entries = try await makePackage(markdown: "# Chapter One\n\nSome prose here.")
        let content = try #require(entries["content.xhtml"])

        #expect(content.contains("\u{2801}"))
        // The print text must not survive into the braille document.
        #expect(!content.contains("Chapter One"))
        #expect(!content.contains("Some prose here"))
    }

    @Test func stylesheetSetsNoFontOrColourProperties() async throws {
        let entries = try await makePackage(markdown: "Text.")
        let css = try #require(entries["style.css"])

        // The reading system owns rendering. Declaring any of these would
        // override the reader's own display settings.
        for forbidden in ["font-family", "font-size", "font-weight", "font-style", "color", "text-decoration"] {
            #expect(!css.contains(forbidden), "stylesheet must not set \(forbidden)")
        }
    }

    @Test func orderedListNumbersAreWrittenIntoTheContent() async throws {
        let entries = try await makePackage(markdown: "1. First\n2. Second")
        let content = try #require(entries["content.xhtml"])

        // eBraille forbids relying on generated markers, so each item carries
        // its own. With the stub every translated string is braille, so the
        // check is that list items contain more than their text alone.
        #expect(content.contains("<li style="))
        #expect(content.contains("ch\">\u{2801}\u{2801}\u{2800}"))
        #expect(content.contains("list-style-type: none") == false)
        let css = try #require(entries["style.css"])
        #expect(css.contains("list-style-type: none"))
    }

    @Test func unorderedListUsesTheUEBBulletInEveryListItem() async throws {
        let entries = try await makePackage(markdown: "- First\n- Second")
        let content = try #require(entries["content.xhtml"])

        #expect(content.components(separatedBy: "ch\">\u{2838}\u{2832}\u{2800}").count - 1 == 2)
    }

    @Test func imageAlternativeTextIsTranslated() async throws {
        let entries = try await makePackage(
            markdown: "![A tactile diagram](diagram.png)"
        )
        let content = try #require(entries["content.xhtml"])

        // Alt text is renderable, so print text there would be read as
        // meaningless cells on a braille display.
        #expect(!content.contains("A tactile diagram"))
    }

    @Test func tactileGraphicsReportsNoneWhenThereAreNoImages() async throws {
        let entries = try await makePackage(markdown: "Just text.")
        let package = try #require(entries["package.opf"])

        #expect(package.contains("<meta property=\"a11y:tactileGraphics\">none</meta>"))
    }

    @Test func tactileSVGIsPackagedAndDeclaredFromTheMarkdownTitle() async throws {
        let fixture = try tactileFixture(
            fileName: "map.svg",
            data: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0L10 10\"/></svg>".utf8)
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let entries = try await makePackage(
            markdown: "![Raised route map](\(fixture.reference) \"tactile\")",
            sourceDirectory: fixture.root
        )
        let package = try #require(entries["package.opf"])
        let content = try #require(entries["content.xhtml"])

        #expect(package.contains("<meta property=\"a11y:tactileGraphics\">SVG</meta>"))
        #expect(package.contains("href=\"content.xhtml\" media-type=\"application/xhtml+xml\" properties=\"svg\""))
        #expect(entries.keys.contains { $0.hasSuffix("map.svg") })
        #expect(content.contains("class=\"tactile-graphic\""))
        #expect(!content.contains("Raised route map"))
    }

    @Test func ordinaryImageDoesNotClaimTactileGraphics() async throws {
        let fixture = try tactileFixture(fileName: "photo.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let entries = try await makePackage(
            markdown: "![A photograph](\(fixture.reference))",
            sourceDirectory: fixture.root
        )
        let package = try #require(entries["package.opf"])
        let content = try #require(entries["content.xhtml"])

        #expect(package.contains("<meta property=\"a11y:tactileGraphics\">none</meta>"))
        #expect(!content.contains("class=\"tactile-graphic\""))
    }

    @Test func missingTactileGraphicFailsInsteadOfBecomingFallbackText() async {
        await #expect(throws: EBrailleExportError.self) {
            _ = try await makePackage(
                markdown: "![Raised map](.ghostwriter-assets-missing/map.svg \"tactile\")"
            )
        }
    }

    @Test func unsafeTactileSVGIsRejected() async throws {
        let fixture = try tactileFixture(
            fileName: "map.svg",
            data: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>bad()</script></svg>".utf8)
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        await #expect(throws: EBrailleExportError.self) {
            _ = try await makePackage(
                markdown: "![Raised map](\(fixture.reference) \"tactile\")",
                sourceDirectory: fixture.root
            )
        }
    }

    @Test func corruptTactileRasterIsRejected() async throws {
        let fixture = try tactileFixture(fileName: "map.png", data: Data([1, 2, 3]))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        await #expect(throws: EBrailleExportError.self) {
            _ = try await makePackage(
                markdown: "![Raised map](\(fixture.reference) \"tactile\")",
                sourceDirectory: fixture.root
            )
        }
    }

    @Test func tactileGraphicRequiresAUsefulDescription() async {
        await #expect(throws: EBrailleExportError.self) {
            _ = try await makePackage(
                markdown: "![](.ghostwriter-assets-missing/map.svg \"tactile\")"
            )
        }
    }

    @Test func navigationDocumentListsHeadings() async throws {
        let entries = try await makePackage(
            markdown: "# One\n\nText.\n\n## Two\n\nMore."
        )
        let nav = try #require(entries["index.html"])

        #expect(nav.contains("epub:type=\"toc\""))
        #expect(nav.contains("content.xhtml#heading-"))
    }

    @Test func navigationIncludesDeepHeadingsAndAccountsForInsertedTitle() async throws {
        let entries = try await makePackage(
            title: "Book title",
            markdown: "# Chapter\n\n#### Detail"
        )
        let nav = try #require(entries["index.html"])
        let content = try #require(entries["content.xhtml"])

        #expect(content.contains("id=\"heading-1\""))
        #expect(content.contains("id=\"heading-2\""))
        #expect(content.contains("id=\"heading-3\""))
        #expect(nav.contains("content.xhtml#heading-2"))
        #expect(nav.contains("content.xhtml#heading-3"))
    }

    @Test func taskListStatesAreWrittenAsBrailleText() async throws {
        let entries = try await makePackage(markdown: "- [x] Done\n- [ ] Waiting")
        let content = try #require(entries["content.xhtml"])

        #expect(!content.contains("Completed:"))
        #expect(!content.contains("Not completed:"))
        #expect(content.components(separatedBy: "<li style=").count - 1 == 2)
    }

    @Test func missingCreatorIsRejectedInsteadOfInvented() async {
        await #expect(throws: EBrailleExportError.self) {
            _ = try await makePackage(
                markdown: "Text.",
                metadata: EBrailleMetadata(creator: "   ", transcriber: "Test Transcriber", grade: .grade2, copyrightYear: "2026")
            )
        }
    }

    @Test func transcriberIsTheOnlyNamedProducer() async throws {
        let entries = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(
                creator: "A Writer",
                transcriber: "Braille Services Ltd",
                grade: .grade2,
                copyrightYear: "2026"
            )
        )
        let package = try #require(entries["package.opf"])

        #expect(package.contains(
            "<meta property=\"a11y:producer\">Braille Services Ltd</meta>"
        ))
        #expect(!package.contains("ghostWriter Markdown"))
        // The transcriber is not the author of the work being transcribed.
        #expect(package.contains("<dc:creator>A Writer</dc:creator>"))
    }

    @Test func missingTranscriberIsRejectedInsteadOfNamingTheSoftware() async {
        await #expect(throws: EBrailleExportError.self) {
            _ = try await makePackage(
                markdown: "Text.",
                metadata: EBrailleMetadata(creator: "A Writer", grade: .grade2, copyrightYear: "2026")
            )
        }
    }

    @Test func recommendedPropertiesAreWrittenWhenSupplied() async throws {
        let entries = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(
                creator: "A Writer",
                transcriber: "Test Transcriber",
                grade: .grade2,
                copyrightYear: "2026",
                source: "urn:isbn:9780000000001",
                publisher: "A Braille Press",
                rights: "Copyright the author. Transcribed under licence.",
                subject: "Geography",
                descriptionText: "A short report, transcribed for classroom use.",
                educationLevel: "Year 4"
            )
        )
        let package = try #require(entries["package.opf"])

        #expect(package.contains("<dc:source>urn:isbn:9780000000001</dc:source>"))
        #expect(package.contains("<dc:publisher>A Braille Press</dc:publisher>"))
        #expect(package.contains("<dc:subject>Geography</dc:subject>"))
        #expect(package.contains(
            "<meta property=\"dcterms:educationLevel\">Year 4</meta>"
        ))
        #expect(package.contains("Transcribed under licence."))
    }

    @Test func recommendedPropertiesAreOmittedWhenBlank() async throws {
        let entries = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(
                creator: "A Writer",
                transcriber: "Test Transcriber",
                grade: .grade2,
                copyrightYear: "2026",
                source: "   ",
                publisher: ""
            )
        )
        let package = try #require(entries["package.opf"])

        // An empty dc:rights asserts that the rights are known to be nothing,
        // which is a worse claim than the element being absent.
        #expect(!package.contains("<dc:source>"))
        #expect(!package.contains("<dc:publisher>"))
        #expect(!package.contains("<dc:rights>"))
        #expect(!package.contains("dcterms:educationLevel"))
    }

    @Test func copyrightDateIsWrittenInAFormTheStandardAllows() async throws {
        let entries = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(
                creator: "A Writer",
                transcriber: "Test Transcriber",
                grade: .grade2,
                copyrightYear: "2026/04/17"
            )
        )
        let package = try #require(entries["package.opf"])

        #expect(package.contains(
            "<meta property=\"dcterms:dateCopyrighted\">2026-04-17</meta>"
        ))
    }

    private func tactileFixture(
        fileName: String,
        data: Data
    ) throws -> (root: URL, reference: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostWriter-tactile-test-\(UUID().uuidString)")
        let directoryName = ".ghostwriter-assets-\(UUID().uuidString.lowercased())"
        let directory = root.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName))
        return (root, "\(directoryName)/\(fileName)")
    }
}

struct BrailleLanguageTagTests {

    @Test func scriptSubtagIsInsertedBeforeTheRegion() {
        #expect(BrailleLanguageTag.brailleTag(from: "en-US") == "en-Brai-US")
        #expect(BrailleLanguageTag.brailleTag(from: "en") == "en-Brai")
        #expect(BrailleLanguageTag.brailleTag(from: "fr-CA") == "fr-Brai-CA")
    }

    @Test func underscoresAreNormalised() {
        // Locale.current.identifier uses underscores, unlike BCP 47.
        #expect(BrailleLanguageTag.brailleTag(from: "en_GB") == "en-Brai-GB")
    }

    @Test func anExistingScriptIsReplacedRatherThanAppended() {
        // Two script subtags would be invalid, and the document is braille
        // regardless of what script the print text used.
        #expect(BrailleLanguageTag.brailleTag(from: "zh-Hans-CN") == "zh-Brai-CN")
    }

    @Test func unreadableTagsFallBackToEnglishBraille() {
        #expect(BrailleLanguageTag.brailleTag(from: "") == "en-Brai")
        #expect(BrailleLanguageTag.brailleTag(from: "!!!") == "en-Brai")
    }

    @Test func languageComesFromTheTableWithoutAnInferredDeviceRegion() {
        #expect(BrailleLanguageTag.brailleTag(from: "en") == "en-Brai")
    }
}
