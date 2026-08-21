//
//  BrailleLanguageTag.swift
//  ghostWriter
//
//  Builds the BCP 47 language tag eBraille requires.
//
//  eBraille asks for the `Brai` script subtag, so `en-US` becomes `en-Brai-US`.
//  That is not string concatenation: the subtag has a fixed position, after the
//  language and before any region, and a tag that already carries a different
//  script needs that script replaced rather than a second one appended. Getting
//  this wrong produces a file that declares itself to be in a language that
//  does not exist.
//

import Foundation

nonisolated enum BrailleLanguageTag {

    /// ISO 15924 code for braille.
    private static let brailleScript = "Brai"

    /// Inserts or replaces the script subtag in a language tag.
    ///
    /// Falls back to `en-Brai` when the tag cannot be read, because a
    /// conforming file with a plausible language is more useful than a
    /// non-conforming one with none.
    static func brailleTag(from languageTag: String) -> String {
        let cleaned = languageTag
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)

        guard let language = parts.first,
              language.count >= 2, language.count <= 3,
              language.allSatisfy(\.isLetter) else {
            return "en-\(brailleScript)"
        }

        // A script subtag is four letters. Anything else in second position is
        // a region or variant and keeps its place after the script.
        let remainder = parts.dropFirst().filter { part in
            !(part.count == 4 && part.allSatisfy(\.isLetter))
        }

        return ([language.lowercased(), brailleScript] + remainder)
            .joined(separator: "-")
    }

    /// A braille tag for `language`, carrying over the region from another
    /// tag when the two languages agree.
    ///
    /// The braille code fixes the language — UEB is English regardless of
    /// where the device is set — but a reader in Britain and one in the United
    /// States both want their own region recorded. Region is only carried over
    /// when the languages match, so a French-locale device exporting English
    /// braille produces `en-Brai`, not `en-Brai-FR`.
    static func brailleTag(from language: String, regionFrom other: String) -> String {
        let base = brailleTag(from: language)
        let baseParts = base.split(separator: "-").map(String.init)
        let otherParts = other.split(separator: "-").map(String.init)

        guard baseParts.count == 2,
              let baseLanguage = baseParts.first,
              let otherLanguage = otherParts.first,
              baseLanguage == otherLanguage,
              otherParts.count > 1 else {
            return base
        }

        let regionOrVariants = otherParts.dropFirst().filter { part in
            !(part.count == 4 && part.allSatisfy(\.isLetter))
        }
        return ([baseLanguage, brailleScript] + regionOrVariants)
            .joined(separator: "-")
    }

    /// The device's language, as a braille tag.
    static func currentBrailleTag() -> String {
        let preferred = Locale.preferredLanguages.first
            ?? Locale.current.identifier
        return brailleTag(from: preferred)
    }
}
