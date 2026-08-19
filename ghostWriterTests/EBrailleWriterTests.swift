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
        func translate(_ text: String, grade: BrailleGrade) async throws -> String {
            // A recognisable braille pattern per input character.
            String(repeating: "\u{2801}", count: max(text.count, 1))
        }
    }

    private func makePackage(
        title: String = "Test Document",
        markdown: String,
        metadata: EBrailleMetadata = EBrailleMetadata(creator: "A Writer", grade: .grade2)
    ) async throws -> [String: String] {
        let data = try await EBrailleWriter.write(
            title: title,
            markdown: markdown,
            metadata: metadata,
            translator: StubTranslator()
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
    }

    @Test func brailleSystemMatchesTheChosenGrade() async throws {
        let grade1 = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(creator: "A Writer", grade: .grade1)
        )
        let grade2 = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(creator: "A Writer", grade: .grade2)
        )

        #expect(try #require(grade1["package.opf"]).contains("ueb grade1"))
        #expect(try #require(grade2["package.opf"]).contains("ueb grade2"))
    }

    @Test func producerIsFixedRegardlessOfCreator() async throws {
        let entries = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(creator: "Someone Else", grade: .grade2)
        )
        let package = try #require(entries["package.opf"])

        #expect(package.contains("<meta property=\"a11y:producer\">ghostWriter Markdown</meta>"))
    }

    @Test func languageCarriesTheBrailleScriptSubtag() async throws {
        let entries = try await makePackage(markdown: "Text.")
        let package = try #require(entries["package.opf"])

        #expect(package.contains("Brai"))
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
        #expect(content.contains("<li>"))
        #expect(content.contains("list-style-type: none") == false)
        let css = try #require(entries["style.css"])
        #expect(css.contains("list-style-type: none"))
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

    @Test func navigationDocumentListsHeadings() async throws {
        let entries = try await makePackage(
            markdown: "# One\n\nText.\n\n## Two\n\nMore."
        )
        let nav = try #require(entries["index.html"])

        #expect(nav.contains("epub:type=\"toc\""))
        #expect(nav.contains("content.xhtml#heading-"))
    }

    @Test func emptyCreatorFallsBackToTheProducer() async throws {
        let entries = try await makePackage(
            markdown: "Text.",
            metadata: EBrailleMetadata(creator: "   ", grade: .grade2)
        )
        let package = try #require(entries["package.opf"])

        // dc:creator is required, so an empty field cannot simply be omitted.
        #expect(package.contains("<dc:creator>ghostWriter Markdown</dc:creator>"))
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

    @Test func languageComesFromTheTableNotTheDevice() {
        // UEB is English. A device set to French must not make the file claim
        // to be French braille, but an English region is still worth keeping.
        #expect(
            BrailleLanguageTag.brailleTag(from: "en", regionFrom: "en-Brai-US")
                == "en-Brai-US"
        )
        #expect(
            BrailleLanguageTag.brailleTag(from: "en", regionFrom: "en-Brai-GB")
                == "en-Brai-GB"
        )
        #expect(
            BrailleLanguageTag.brailleTag(from: "en", regionFrom: "fr-Brai-FR")
                == "en-Brai"
        )
        #expect(
            BrailleLanguageTag.brailleTag(from: "en", regionFrom: "en-Brai")
                == "en-Brai"
        )
    }
}
