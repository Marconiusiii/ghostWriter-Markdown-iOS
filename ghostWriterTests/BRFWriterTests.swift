import Foundation
import Testing
@testable import ghostWriter

struct BRFWriterTests {
    private actor RecordingTranslator: BrailleTranslator {
        private(set) var inputs: [BrailleTranslationInput] = []

        func translate(
            _ input: BrailleTranslationInput,
            grade: BrailleGrade
        ) async throws -> String {
            inputs.append(input)
            return input.text.map { character in
                switch character {
                case " ": return "\u{2800}"
                case "\n": return "\n"
                default: return "\u{2801}"
                }
            }.joined()
        }
    }

    @Test func oversizedWordIsDividedWithoutExceedingTheWidth() {
        let lines = BRFWriter.wrapped(
            "abcdefghijklmnop",
            width: 6,
            start: 0,
            runover: 2
        )

        #expect(lines == ["abcde-", "  fgh-", "  ijk-", "  lmn-", "  op"])
        #expect(lines.allSatisfy { $0.count <= 6 })
    }

    @Test func fortyThreeCellSequenceExportsAtFortyCells() async throws {
        let translator = RecordingTranslator()
        let data = try await BRFWriter.write(
            markdown: String(repeating: "a", count: 43),
            title: "",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 40, linesPerPage: 25),
            translator: translator
        )
        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .filter { !$0.isEmpty }

        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("  "))
        #expect(lines[0].hasSuffix("-"))
        #expect(lines.allSatisfy { $0.count <= 40 })
        #expect(lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .joined()
            .replacingOccurrences(of: "-", with: "").count == 43)
    }

    @Test func realLiblouisOversizedWordExportsWithinFortyCells() async throws {
        let data = try await BRFWriter.write(
            markdown: "pneumonoultramicroscopicsilicovolcanoconiosis",
            title: "",
            grade: .grade1,
            pageSetup: .standard,
            translator: LiblouisBridge.shared
        )
        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .filter { !$0.isEmpty }

        #expect(lines.count > 1)
        #expect(lines[0].hasSuffix("-"))
        #expect(lines.allSatisfy { $0.count <= 40 })
    }

    @Test func oversizedSequencePrefersAnExistingHyphen() {
        let lines = BRFWriter.wrapped(
            "abc-defgh",
            width: 6,
            start: 0,
            runover: 0
        )

        #expect(lines == ["abc-", "defgh"])
    }

    @Test func oversizedListWordUsesTheListRunoverMargin() async throws {
        let translator = RecordingTranslator()
        let data = try await BRFWriter.write(
            markdown: "- \(String(repeating: "a", count: 43))",
            title: "",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 40, linesPerPage: 25),
            translator: translator
        )
        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .filter { !$0.isEmpty }

        #expect(lines.count == 3)
        #expect(lines[0] == "_4")
        #expect(lines.dropFirst().allSatisfy { $0.hasPrefix("  ") })
        #expect(lines.allSatisfy { $0.count <= 40 })
    }

    @Test func matchingTitleHeadingIsTranslatedOnlyOnce() async throws {
        let translator = RecordingTranslator()
        _ = try await BRFWriter.write(
            markdown: "# Same title\n\nBody.",
            title: "Same title",
            grade: .grade2,
            translator: translator
        )

        let inputs = await translator.inputs
        #expect(inputs.filter { $0.text == "Same title" }.count == 1)
    }

    @Test func taskStateIsIncludedInTranslation() async throws {
        let translator = RecordingTranslator()
        _ = try await BRFWriter.write(
            markdown: "- [x] Finished\n- [ ] Waiting",
            title: "",
            grade: .grade2,
            translator: translator
        )

        let text = await translator.inputs.map(\.text)
        #expect(text.contains("Completed:"))
        #expect(text.contains("Not completed:"))
    }

    @Test func tableCellsPreserveInlineEmphasis() async throws {
        let translator = RecordingTranslator()
        _ = try await BRFWriter.write(
            markdown: "| Name |\n| --- |\n| **Important** |",
            title: "",
            grade: .grade2,
            translator: translator
        )

        let inputs = await translator.inputs
        let emphasized = inputs.first { $0.text == "Important" }
        #expect(emphasized != nil)
        #expect(emphasized?.typeforms.allSatisfy { $0.contains(.bold) } == true)
    }

    @Test func emphasizedGradeTwoDocumentUsesCustomSmallPages() async throws {
        let markdown = """
        This is about **braille confidence drift**.

        **EXPECT. EXPOSE. ENABLE. EMPOWER. ENJOY.**

        **Maximum literacy. Maximum independence. Maximum choice.**
        """
        let data = try await BRFWriter.write(
            markdown: markdown,
            title: "Braille Confidence",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 20, linesPerPage: 10),
            translator: LiblouisBridge.shared
        )
        let pages = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\r\n\u{000C}")

        #expect(pages.count > 1)
        for page in pages {
            var lines = page.components(separatedBy: "\r\n")
            if lines.last?.isEmpty == true { lines.removeLast() }
            #expect(lines.count <= 10)
            #expect(lines.allSatisfy { $0.count <= 20 })
        }
    }

    @Test func displayPurposePreservesExistingOutput() async throws {
        let translator = RecordingTranslator()
        let implicit = try await BRFWriter.write(
            markdown: "A short document.",
            title: "Title",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 20, linesPerPage: 10),
            translator: translator
        )
        let explicit = try await BRFWriter.write(
            markdown: "A short document.",
            title: "Title",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 20, linesPerPage: 10),
            outputPurpose: .brailleDisplay,
            translator: RecordingTranslator()
        )

        #expect(implicit == explicit)
    }

    @Test func embossedPagesReserveAndNumberTheFinalLine() async throws {
        let data = try await BRFWriter.write(
            markdown: Array(repeating: "One two three four five.", count: 20)
                .joined(separator: "\n\n"),
            title: "",
            grade: .grade1,
            pageSetup: .init(cellsPerLine: 20, linesPerPage: 10),
            outputPurpose: .embossedPages,
            translator: LiblouisBridge.shared
        )
        let output = String(decoding: data, as: UTF8.self)
        #expect(output.hasSuffix("\r\n"))
        let withoutFinalCRLF = String(output.dropLast())
        let pages = withoutFinalCRLF.components(separatedBy: "\r\n\u{000C}")

        #expect(pages.count > 1)
        for (index, page) in pages.enumerated() {
            let lines = page.components(separatedBy: "\r\n")
            let expectedNumber = try BRFWriter.asciiBraille(
                try await LiblouisBridge.shared.translate("\(index + 1)", grade: .grade1)
            )
            #expect(lines.count == 10)
            #expect(lines.allSatisfy { $0.count <= 20 })
            #expect(lines.last?.count == 20)
            #expect(lines.last?.hasSuffix(expectedNumber) == true)
        }
    }

    @Test func embossedPagesRequireRoomForContentAndPageNumber() async {
        await #expect(throws: BRFExportError.pageTooShortForPageNumber) {
            try await BRFWriter.write(
                markdown: "Text",
                title: "",
                grade: .grade2,
                pageSetup: .init(cellsPerLine: 20, linesPerPage: 1),
                outputPurpose: .embossedPages,
                translator: RecordingTranslator()
            )
        }
    }

    @Test func embossedPagesWithoutNumbersUseEverySelectedLine() async throws {
        let data = try await BRFWriter.write(
            markdown: Array(repeating: "One.", count: 20)
                .joined(separator: "\n\n"),
            title: "",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 20, linesPerPage: 10),
            outputPurpose: .embossedPages,
            includeBraillePageNumbers: false,
            translator: RecordingTranslator()
        )
        let output = String(decoding: data, as: UTF8.self)
        let withoutFinalCRLF = String(output.dropLast(2))
        let pages = withoutFinalCRLF.components(separatedBy: "\r\n\u{000C}")

        #expect(pages.count == 2)
        for page in pages {
            let lines = page.components(separatedBy: "\r\n")
            #expect(lines.count == 10)
            #expect(lines.allSatisfy { $0.count <= 20 })
        }
    }

    @Test func brfLinksKeepTheirDestinationsWithoutDuplicatingBareURLs() async throws {
        let translator = RecordingTranslator()
        _ = try await BRFWriter.write(
            markdown: "[Guide](https://example.com) and <https://openai.com>.",
            title: "",
            grade: .grade2,
            translator: translator
        )

        let inputs = await translator.inputs.map(\.text)
        #expect(inputs.contains("Guide"))
        #expect(inputs.contains("(https://example.com)"))
        #expect(inputs.filter { $0 == "https://openai.com" }.count == 1)
    }

    @Test func internalLinksKeepTheirLabelsWithoutPrintingFragments() async throws {
        let translator = RecordingTranslator()
        _ = try await BRFWriter.write(
            markdown: "[Introduction](#introduction)",
            title: "",
            grade: .grade2,
            translator: translator
        )

        let inputs = await translator.inputs.map(\.text)
        #expect(inputs.contains("Introduction"))
        #expect(!inputs.contains { $0.contains("#introduction") })
    }

    @Test func longElectronicAddressUsesUEBContinuationInsteadOfHyphen() async throws {
        let destination = "https://example.com/" + String(repeating: "a", count: 50)
        let data = try await BRFWriter.write(
            markdown: "[Guide](\(destination))",
            title: "",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 20, linesPerPage: 25),
            translator: RecordingTranslator()
        )
        let output = String(decoding: data, as: UTF8.self)

        #expect(output.contains("\""))
        #expect(!output.contains("-"))
        #expect(output.components(separatedBy: "\r\n")
            .allSatisfy { $0.count <= 20 })
    }

    @Test func unorderedItemsUseBrailleBulletsAndSeparateLines() async throws {
        let translator = RecordingTranslator()
        let data = try await BRFWriter.write(
            markdown: "- First\n- Second\n- Third",
            title: "",
            grade: .grade2,
            translator: translator
        )
        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .filter { !$0.isEmpty }

        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.hasPrefix("_4 ") })
    }

    @Test func nestedListUsesOneCommonRunoverCell() async throws {
        let translator = RecordingTranslator()
        let data = try await BRFWriter.write(
            markdown: "- Outer item with enough words to wrap here\n  - Inner item with enough words to wrap too",
            title: "",
            grade: .grade2,
            pageSetup: .init(cellsPerLine: 20, linesPerPage: 25),
            translator: translator
        )
        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .filter { !$0.isEmpty }

        #expect(lines.contains { $0.hasPrefix("    ") && !$0.hasPrefix("     ") })
        #expect(lines.contains { $0.hasPrefix("  _4 ") })
    }

    @Test func preformattedWrappingPreservesSpacesAndBlankLines() {
        #expect(BRFWriter.wrappedPreformatted("a  b", width: 8, margin: 2) == ["  a  b"])
        #expect(BRFWriter.wrappedPreformatted("", width: 8, margin: 2) == ["  "])
    }

    @Test func wrappedHeadingMovesIntactToTheNextPage() {
        let output = BRFWriter.paginate(
            [
                .init(lines: Array(repeating: "body", count: 6), isHeading: false),
                .init(
                    lines: ["", "heading one", "heading two", "heading three"],
                    isHeading: true
                ),
                .init(lines: ["following"], isHeading: false)
            ],
            linesPerPage: 10
        )
        let pages = output.components(separatedBy: "\r\n\u{000C}")

        #expect(pages.count == 2)
        #expect(!pages[0].contains("heading"))
        #expect(pages[1].contains("heading one\r\nheading two\r\nheading three"))
        #expect(pages[1].contains("heading three\r\nfollowing"))
    }

    @Test func headingKeepsTheFirstFollowingLineOnItsPage() {
        let output = BRFWriter.paginate(
            [
                .init(lines: Array(repeating: "body", count: 6), isHeading: false),
                .init(lines: ["", "heading one", "heading two"], isHeading: true),
                .init(lines: ["following"], isHeading: false)
            ],
            linesPerPage: 10
        )
        let pages = output.components(separatedBy: "\r\n\u{000C}")

        #expect(pages.count == 1)
        #expect(pages[0].contains("heading two\r\nfollowing"))
        let lines = pages[0].components(separatedBy: "\r\n")
            .filter { !$0.isEmpty }
        #expect(lines.count <= 10)
        #expect(lines.allSatisfy { $0.count <= 20 })
    }

    @Test func codeTabsAreExpandedBeforeFixedCellTranslation() async throws {
        let translator = RecordingTranslator()
        _ = try await BRFWriter.write(
            markdown: "```\nleft\tright\n```",
            title: "",
            grade: .grade2,
            translator: translator
        )

        let inputs = await translator.inputs
        #expect(inputs.contains { $0.text == "left    right" })
        #expect(!inputs.contains { $0.text.contains("\t") })
    }

    @Test func asciiConversionRejectsEightDotBrailleAndPrintText() {
        #expect(throws: BRFExportError.self) {
            _ = try BRFWriter.asciiBraille("\u{2840}")
        }
        #expect(throws: BRFExportError.self) {
            _ = try BRFWriter.asciiBraille("A")
        }
    }

    @Test func everySixDotCellUsesStandardBrailleASCII() throws {
        var unicodeBraille = ""
        for value in 0..<64 {
            unicodeBraille.unicodeScalars.append(UnicodeScalar(0x2800 + value)!)
        }

        let expected = " A1B'K2L@CIF/MSP\"E3H9O6R^DJG>NTQ,*5<-U8V.%[$+X!&;:4\\0Z7(_?W]#Y)="
        #expect(try BRFWriter.asciiBraille(unicodeBraille) == expected)
    }

    @Test func gradeTwoUsesExpectedUEBContractionsInBRF() async throws {
        let unicodeBraille = try await LiblouisBridge.shared.translate(
            "words how show Markdown",
            grade: .grade2
        )

        #expect(try BRFWriter.asciiBraille(unicodeBraille) == "^WS H[ %[ ,M>KD[N")
    }

    @Test func owAndWordsCellsUseStandardBRFCharacters() async throws {
        let ow = try await LiblouisBridge.shared.translate("ow", grade: .grade2)
        let words = try await LiblouisBridge.shared.translate("words", grade: .grade2)

        #expect(try BRFWriter.asciiBraille(ow) == "[")
        #expect(try BRFWriter.asciiBraille(words) == "^WS")
    }

    @Test func welcomeDocumentUsesOnlyStandardBRFAndExpectedContractions() async throws {
        let markdown = try WelcomeDocument.bundledMarkdown()
        let data = try await BRFWriter.write(
            markdown: markdown,
            title: WelcomeDocument.name,
            grade: .grade2,
            pageSetup: .standard,
            translator: LiblouisBridge.shared
        )
        let allowed = Set(
            " A1B'K2L@CIF/MSP\"E3H9O6R^DJG>NTQ,*5<-U8V.%[$+X!&;:4\\0Z7(_?W]#Y)="
                .utf8
        ).union([10, 12, 13])
        let brf = String(decoding: data, as: UTF8.self)

        #expect(data.allSatisfy { allowed.contains($0) })
        #expect(brf.contains("^WS"))
        #expect(brf.contains("H["))
    }
}
