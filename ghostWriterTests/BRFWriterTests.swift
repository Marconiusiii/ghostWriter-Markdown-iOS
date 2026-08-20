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
            return String(repeating: "\u{2801}", count: input.text.count)
        }
    }

    @Test func oversizedWordNeverExceedsSelectedWidth() {
        let lines = BRFWriter.wrapped(
            "abcdefghijklmnop",
            width: 6,
            start: 0,
            runover: 2
        )

        #expect(lines.allSatisfy { $0.count <= 6 })
        #expect(lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined() == "abcdefghijklmnop")
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
}
