//
//  BrailleTranslator.swift
//  ghostWriter
//
//  The contract between the eBraille writer and whatever performs translation.
//
//  The writer needs braille characters and a name for the braille system it
//  used — eBraille requires that system to be declared in the publication's
//  metadata, so producing the braille and naming it are one responsibility
//  rather than two. Keeping this a protocol also means the writer's tests can
//  run against a predictable stub instead of loading translation tables.
//

import Foundation

/// A braille code a document can be translated into.
///
/// The raw value is the table liblouis resolves, and `systemName` is what
/// eBraille records in `a11y:brailleSystem`. They are deliberately kept
/// together: a file whose metadata disagrees with its contents is worse than
/// one that offers fewer choices.
nonisolated enum BrailleGrade: String, CaseIterable, Identifiable, Sendable {
    case grade1 = "en-ueb-g1.ctb"
    case grade2 = "en-ueb-g2.ctb"

    var id: String { rawValue }

    /// Table file this grade translates through.
    var tableName: String { rawValue }

    /// Value written to `a11y:brailleSystem` in the package document.
    ///
    /// The form is `[code] [grade]` from the eBraille Braille Codes Registry,
    /// where the grade is spelled `grade1`/`grade2` with no space. "UEB
    /// grade 2" reads naturally but is not the registry syntax, and the spec
    /// asks for a registry value.
    ///
    /// The code is `ueb`, not a national variant: liblouis translates these
    /// through the generic Unified English Braille tables, which are not
    /// BANA-specific. Claiming EBAE or a country code would describe a
    /// different transcription than the one in the file.
    var systemName: String {
        switch self {
        case .grade1: return "ueb grade1"
        case .grade2: return "ueb grade2"
        }
    }

    /// The language this grade's table transcribes, as a BCP 47 tag.
    ///
    /// UEB is English. The document language must agree with the table that
    /// produced the braille, or the file claims a language its contents are
    /// not in.
    var languageTag: String { "en" }

    /// Wording for the export sheet's grade picker.
    var displayName: String {
        switch self {
        case .grade1: return "Grade 1 (uncontracted)"
        case .grade2: return "Grade 2 (contracted)"
        }
    }
}

nonisolated protocol BrailleTranslator: Sendable {
    /// Translates print text into Unicode braille pattern characters.
    ///
    /// The result contains only characters from the U+2800 block plus spaces
    /// and newlines, which is what eBraille permits in renderable text.
    func translate(_ text: String, grade: BrailleGrade) async throws -> String
}
