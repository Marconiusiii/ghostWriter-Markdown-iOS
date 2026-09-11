import Foundation

nonisolated enum ThematicSeparator: String, CaseIterable, Identifiable, Sendable {
    case none, asterisks, spacedAsterisks, spacedHyphens, spacedPeriods, spacedBullets

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: String(localized: "None")
        case .asterisks: String(localized: "Three asterisks")
        case .spacedAsterisks: String(localized: "Three spaced asterisks")
        case .spacedHyphens: String(localized: "Three spaced hyphens")
        case .spacedPeriods: String(localized: "Three spaced periods")
        case .spacedBullets: String(localized: "Three spaced bullets")
        }
    }

    var text: String? {
        switch self {
        case .none: nil
        case .asterisks: "***"
        case .spacedAsterisks: "* * *"
        case .spacedHyphens: "- - -"
        case .spacedPeriods: ". . ."
        case .spacedBullets: "• • •"
        }
    }
}
