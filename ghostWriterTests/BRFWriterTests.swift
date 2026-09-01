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
