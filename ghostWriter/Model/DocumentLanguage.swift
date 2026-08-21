//
//  DocumentLanguage.swift
//  ghostWriter
//
//  Language metadata for one document. This remains library metadata so a
//  writer's Markdown source is never modified merely by changing an export
//  setting.
//

import Foundation

nonisolated enum DocumentLanguage {
    static let automatic = ""

    static let commonTags = [
        "en", "es", "fr", "de", "it", "pt", "nl", "pl", "ca", "eu",
        "gl", "ar", "he", "hi", "ja", "ko", "zh-Hans", "zh-Hant"
    ]

    static func resolvedTag(_ storedTag: String?) -> String {
        let normalized = normalizedTag(storedTag ?? "")
        guard !normalized.isEmpty else {
            return normalizedTag(
                Locale.preferredLanguages.first
                    ?? Locale.current.identifier
            )
        }
        return normalized
    }

    static func normalizedTag(_ tag: String) -> String {
        let cleaned = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !cleaned.isEmpty else { return automatic }

        let components = cleaned.split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)
        guard let language = components.first,
              language.count >= 2, language.count <= 3,
              language.allSatisfy(\.isLetter) else {
            return automatic
        }

        return ([language.lowercased()] + components.dropFirst().enumerated().map { index, part in
            if part.count == 4, part.allSatisfy(\.isLetter) {
                return part.prefix(1).uppercased() + part.dropFirst().lowercased()
            }
            if (part.count == 2 && part.allSatisfy(\.isLetter))
                || (part.count == 3 && part.allSatisfy(\.isNumber)) {
                return part.uppercased()
            }
            return part.lowercased()
        }).joined(separator: "-")
    }

    static func baseLanguage(of tag: String) -> String {
        resolvedTag(tag).split(separator: "-").first.map(String.init) ?? "en"
    }

    static func localizedName(for tag: String, locale: Locale = .current) -> String {
        let resolved = resolvedTag(tag)
        return locale.localizedString(forIdentifier: resolved)
            ?? locale.localizedString(forLanguageCode: baseLanguage(of: resolved))
            ?? resolved
    }

    static func displayName(for storedTag: String, locale: Locale = .current) -> String {
        storedTag.isEmpty
            ? String(localized: "Automatic (device language)")
            : localizedName(for: storedTag, locale: locale)
    }
}
