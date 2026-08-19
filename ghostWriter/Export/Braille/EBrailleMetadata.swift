//
//  EBrailleMetadata.swift
//  ghostWriter
//
//  The facts eBraille requires a publication to declare about itself.
//
//  Unlike EPUB, eBraille makes a specific set of properties mandatory, each
//  appearing exactly once. A file missing any of them is not merely sparse, it
//  is non-conforming — so these are gathered from the writer before export
//  rather than guessed at afterwards.
//

import Foundation

nonisolated struct EBrailleMetadata: Equatable, Sendable {

    /// Fixed. ghostWriter produced the file, so this is a statement of fact
    /// rather than a preference, and the export sheet shows it read-only.
    static let producer = "ghostWriter Markdown"

    /// The formatting standard the exported layout follows.
    ///
    /// Braille layout is national: cell positions for headings, paragraphs,
    /// and lists differ between BANA, UKAAF, and the Australian Braille
    /// Authority, even when all three transcribe into the same UEB code. The
    /// stylesheet implements BANA *Braille Formats* (2016), so the file says
    /// so — a reader or agency can then tell which conventions to expect
    /// rather than inferring them from the layout.
    static let formatStandard = "BANA Braille Formats 2016"

    /// Written to `dc:format`. The standard requires this exact string.
    static let formatIdentifier = "eBraille 1.0"

    var creator: String
    var grade: BrailleGrade

    /// Written to `dcterms:dateCopyrighted`. Year alone is valid and is the
    /// least the writer has to think about.
    var copyrightYear: String

    /// Whether the file contains the whole of the source work. A partial
    /// transcription is legitimate — a single chapter, say — but a reader is
    /// entitled to know which they have.
    var isCompleteTranscription: Bool

    /// Six-dot braille throughout. Eight-dot is used for computer braille
    /// codes, which is not what a markdown document translates into, so this
    /// is fixed rather than offered as a choice that would only mislead.
    static let cellType = "6"

    init(
        creator: String = "",
        grade: BrailleGrade = .grade2,
        copyrightYear: String = "",
        isCompleteTranscription: Bool = true
    ) {
        self.creator = creator
        self.grade = grade
        self.copyrightYear = copyrightYear
        self.isCompleteTranscription = isCompleteTranscription
    }

    /// A creator is required by the standard, so an empty field cannot simply
    /// be omitted. Falling back to the producer keeps the file conforming and
    /// is honest about where it came from.
    var effectiveCreator: String {
        let trimmed = creator.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.producer : trimmed
    }

    /// Defaults to the current year when the writer leaves it blank.
    var effectiveCopyrightYear: String {
        let trimmed = copyrightYear.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return String(Calendar.current.component(.year, from: Date()))
        }
        return trimmed
    }
}
