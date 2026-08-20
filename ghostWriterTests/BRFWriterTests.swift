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

    @Test func oversizedWordIsKeptWholeForAnExplicitGeometryError() {
        let lines = BRFWriter.wrapped(
            "abcdefghijklmnop",
            width: 6,
            start: 0,
            runover: 2
        )

        #expect(lines == ["abcdefghijklmnop"])
    }

    @Test func exportRejectsAWidthThatCannotContainACompleteBrailleWord() async {
        let translator = RecordingTranslator()

        await #expect(throws: BRFExportError.self) {
            _ = try await BRFWriter.write(
                markdown: "elephantine",
                title: "",
                grade: .grade2,
                pageSetup: .init(cellsPerLine: 6, linesPerPage: 25),
                translator: translator
            )
        }
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
}
