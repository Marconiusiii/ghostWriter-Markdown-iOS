//
//  BrailleTranslationTests.swift
//  ghostWriterTests
//
//  Covers translation through liblouis in both grades.
//
//  The assertions check two separate things, because either can fail alone. The
//  cell counts confirm the right table was used — grade 2 contracts and grade 1
//  does not, so identical counts would mean grade 2 silently fell back. The
//  character range checks confirm the output is Unicode braille rather than the
//  ASCII braille liblouis produces by default, which is the failure that would
//  otherwise reach a reader's display as gibberish.
//

import Testing
@testable import ghostWriter

struct BrailleTranslationTests {

    private let translator = LiblouisBridge.shared

    /// True when every character is a braille pattern, a space, or a newline —
    /// the only characters eBraille allows in renderable text.
    private func isUnicodeBraille(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            (0x2800...0x28FF).contains(scalar.value)
                || scalar == " " || scalar == "\n"
        }
    }

    @Test func grade1TranslatesUncontracted() async throws {
        let braille = try await translator.translate("the quick brown fox", grade: .grade1)

        #expect(isUnicodeBraille(braille))
        // Uncontracted braille maps letter for letter, so the cell count
        // matches the input length.
        #expect(braille.count == 19)
    }

    @Test func grade2ContractsWhereGrade1DoesNot() async throws {
        let text = "the quick brown fox knows braille"
        let grade1 = try await translator.translate(text, grade: .grade1)
        let grade2 = try await translator.translate(text, grade: .grade2)

        #expect(isUnicodeBraille(grade1))
        #expect(isUnicodeBraille(grade2))
        // The point of grade 2: "the" becomes one cell, "knows" and "braille"
        // contract too. Equal lengths would mean the table did not load.
        #expect(grade2.count < grade1.count)
        #expect(grade1.count == text.count)
    }

    @Test func grade2UsesTheExpectedOwAndWordsContractions() async throws {
        let braille = try await translator.translate("brown words", grade: .grade2)

        // brown: b, r, ow, n. words: dots 45, w, s.
        let expected = "\u{2803}\u{2817}\u{282A}\u{281D}\u{2800}\u{2818}\u{283A}\u{280E}"
        #expect(braille == expected)
    }

    @Test func capitalsAndNumbersGainIndicators() async throws {
        // Braille marks capitals and numbers with indicator cells, so this
        // output is longer than its input rather than shorter. It is the case
        // that breaks a translator which sizes its buffer to the input.
        let braille = try await translator.translate("26 FILES", grade: .grade1)

        #expect(isUnicodeBraille(braille))
        #expect(braille.count > "26 FILES".count)
    }

    @Test func emptyTextTranslatesToEmpty() async throws {
        let braille = try await translator.translate("", grade: .grade2)

        #expect(braille.isEmpty)
    }

    @Test func longTextIsNotTruncated() async throws {
        // Exercises the output buffer's growth path. A translator that sized
        // its buffer once and trusted it would return a clipped document here,
        // which is a silent corruption rather than a visible error.
        let sentence = "Braille is a tactile writing system used by people who are blind. "
        let text = String(repeating: sentence, count: 200)

        let braille = try await translator.translate(text, grade: .grade2)

        #expect(isUnicodeBraille(braille))
        // Contracted, so shorter than the print text, but still substantial —
        // a truncated result would come back far smaller than this.
        #expect(braille.count > text.count / 2)
    }

    @Test func emphasisTypeformsProduceBrailleIndicators() async throws {
        let text = "important"
        let plain = try await translator.translate(text, grade: .grade2)
        let bold = try await translator.translate(
            BrailleTranslationInput(
                text: text,
                typeforms: Array(repeating: .bold, count: text.utf16.count)
            ),
            grade: .grade2
        )

        #expect(isUnicodeBraille(bold))
        #expect(bold != plain)
        #expect(bold.count > plain.count)
    }

    @Test func styledGrade2OutputCanGrowBeyondItsPrintInput() async throws {
        let text = "A1"
        let input = BrailleTranslationInput(
            text: text,
            typeforms: Array(repeating: .bold, count: text.utf16.count)
        )

        // liblouis writes typeform results for the expanded braille output
        // back into the caller's buffer. Repeating this translation makes an
        // input-sized allocation reliably expose its heap overwrite under
        // Address Sanitizer instead of allowing a later save-sheet operation
        // to appear responsible for the crash.
        for _ in 0..<128 {
            let braille = try await translator.translate(input, grade: .grade2)
            #expect(isUnicodeBraille(braille))
            #expect(braille.count > text.count)
        }
    }

    @Test func gradeMetadataNamesMatchTheStandard() {
        // These strings are written into the publication's a11y:brailleSystem
        // metadata, so they are part of the file format rather than UI wording.
        #expect(BrailleGrade.grade1.systemName == "ueb grade1")
        #expect(BrailleGrade.grade2.systemName == "ueb grade2")
        #expect(BrailleGrade.grade1.tableName == "en-ueb-g1.ctb")
        #expect(BrailleGrade.grade2.tableName == "en-ueb-g2.ctb")
        #expect(BrailleGrade.spanishGrade1.systemName == "Spanish grade1")
        #expect(BrailleGrade.spanishGrade2.systemName == "Spanish grade2")
        #expect(BrailleGrade.spanishGrade1.tableName == "es-g1.ctb")
        #expect(BrailleGrade.spanishGrade2.tableName == "es-g2.ctb")
    }

    @Test func spanishGrade1HandlesAccentsAndInvertedPunctuation() async throws {
        let braille = try await translator.translate(
            "¡El niño preguntó: ¿qué canción?",
            grade: .spanishGrade1
        )

        #expect(isUnicodeBraille(braille))
        #expect(!braille.isEmpty)
        #expect(braille.contains("\u{2816}"))
        #expect(braille.contains("\u{2822}"))
    }

    @Test func spanishGrade2ContractsSpanishText() async throws {
        let text = "que de la el los las del"
        let grade1 = try await translator.translate(text, grade: .spanishGrade1)
        let grade2 = try await translator.translate(text, grade: .spanishGrade2)

        #expect(isUnicodeBraille(grade1))
        #expect(isUnicodeBraille(grade2))
        #expect(grade2 != grade1)
        #expect(grade2.count < grade1.count)
    }
}
