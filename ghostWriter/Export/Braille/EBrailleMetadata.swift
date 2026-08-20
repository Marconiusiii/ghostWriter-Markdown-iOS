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
//  The spec also marks six properties RECOMMENDED. They are not conformance
//  requirements, but they are the fields that make a transcription usable to
//  the people who receive it: what work it came from, who may copy it, what
//  reading level it was cut for. Those are carried here too, and omitted from
//  the package document when left blank rather than written empty.
//

import Foundation

nonisolated struct EBrailleMetadata: Equatable, Sendable {

    /// Written to `dc:format`. The standard requires this exact string.
    static let formatIdentifier = "eBraille 1.0"

    /// Six-dot braille throughout. Eight-dot is used for computer braille
    /// codes, which is not what a markdown document translates into, so this
    /// is fixed rather than offered as a choice that would only mislead.
    static let cellType = "6"

    // MARK: - Required by the standard

    /// `dc:creator`. The author, editor, or equivalent of the work that was
    /// transcribed — not the person who transcribed it.
    var creator: String

    /// `a11y:producer`. The person or agency that produced the braille.
    /// ghostWriter is always listed as a producer as well; this names the
    /// human or organisation responsible for the transcription.
    var transcriber: String

    var grade: BrailleGrade

    /// Written to `dcterms:dateCopyrighted`. The spec requires ISO 8601 in one
    /// of three forms — `YYYY`, `YYYY-MM`, or `YYYY-MM-DD` — so anything else
    /// is corrected before it reaches the file.
    var copyrightYear: String

    /// Whether the file contains the whole of the source work. A partial
    /// transcription is legitimate — a single chapter, say — but a reader is
    /// entitled to know which they have.
    var isCompleteTranscription: Bool

    // MARK: - Recommended by the standard

    /// `dc:source`. The work this is a transcription of. The spec asks for a
    /// URN where one exists; an ISBN or a plain title is still more use than
    /// nothing, so no format is imposed.
    var source: String

    /// `dc:publisher`. Who published the braille edition.
    var publisher: String

    /// `dc:rights`. Who holds the rights and on what terms. Distinct from the
    /// copyright year, which records only when.
    var rights: String

    /// `dc:subject`. A human-readable subject heading.
    var subject: String

    /// `dc:description`. A free-text account of the publication.
    var descriptionText: String

    /// `dcterms:educationLevel`. The grade or year band the material was
    /// produced for — routinely recorded in braille production, where the
    /// same text is cut differently for different levels.
    var educationLevel: String

    init(
        creator: String = "",
        transcriber: String = "",
        grade: BrailleGrade = .grade2,
        copyrightYear: String = "",
        isCompleteTranscription: Bool = true,
        source: String = "",
        publisher: String = "",
        rights: String = "",
        subject: String = "",
        descriptionText: String = "",
        educationLevel: String = ""
    ) {
        self.creator = creator
        self.transcriber = transcriber
        self.grade = grade
        self.copyrightYear = copyrightYear
        self.isCompleteTranscription = isCompleteTranscription
        self.source = source
        self.publisher = publisher
        self.rights = rights
        self.subject = subject
        self.descriptionText = descriptionText
        self.educationLevel = educationLevel
    }

    // MARK: - Values as written to the file

    var effectiveCreator: String {
        creator.trimmed
    }

    var effectiveProducers: [String] {
        let transcriber = transcriber.trimmed
        return transcriber.isEmpty ? [] : [transcriber]
    }

    var effectiveCopyrightYear: String? {
        Self.normalizedCopyrightDate(copyrightYear)
    }

    /// Returns `date` in one of the three permitted ISO 8601 forms, or `nil`
    /// when it cannot be read as a date at all.
    ///
    /// Separators are accepted liberally — a writer typing slashes means the
    /// same thing as one typing hyphens — but the result is always written
    /// with hyphens, and the month and day are range-checked so that a typo
    /// cannot produce a date the spec would reject.
    static func normalizedCopyrightDate(_ date: String) -> String? {
        let cleaned = date.trimmed.replacingOccurrences(
            of: "[/.]",
            with: "-",
            options: .regularExpression
        )
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)
        guard let yearPart = parts.first,
              yearPart.count == 4,
              let year = Int(yearPart),
              year > 0
        else { return nil }

        let yearText = String(format: "%04d", year)
        guard parts.count > 1 else { return yearText }

        guard let month = Int(parts[1]), (1...12).contains(month) else {
            return yearText
        }
        let monthText = String(format: "%02d", month)
        guard parts.count > 2 else { return "\(yearText)-\(monthText)" }

        guard let day = Int(parts[2]), (1...31).contains(day) else {
            return "\(yearText)-\(monthText)"
        }

        // A day the month does not have — 30 February — is not a date, and
        // writing one would make the file non-conforming. `date(from:)` alone
        // does not catch this: it rolls the overflow forward into the next
        // month rather than returning nil, so February 30th silently becomes
        // March 2nd. The components are read back out and compared to confirm
        // the calendar understood the same date that was asked for.
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let resolved = calendar.date(from: components),
              calendar.component(.year, from: resolved) == year,
              calendar.component(.month, from: resolved) == month,
              calendar.component(.day, from: resolved) == day
        else {
            return "\(yearText)-\(monthText)"
        }

        return "\(yearText)-\(monthText)-\(String(format: "%02d", day))"
    }

    var validationMessage: String? {
        if effectiveCreator.isEmpty {
            return "Enter the author or enter Unknown when the author is not known."
        }
        if effectiveProducers.isEmpty {
            return "Enter the person or organization responsible for the braille transcription."
        }
        if effectiveCopyrightYear == nil {
            return "Enter a copyright date as a year, year and month, or full date."
        }
        return nil
    }
}

private extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
