//
//  SortOrder.swift
//  ghostWriter
//
//  How the library list is ordered. Kept as its own type so both the sort menu
//  and the persisted setting refer to the same list of options.
//

import Foundation

enum DocumentSortField: String, CaseIterable, Identifiable {
    case name
    case created
    case modified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .created: return "Date Created"
        case .modified: return "Date Modified"
        }
    }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    /// Direction labels are phrased per field, because "ascending" is opaque
    /// when spoken aloud but "oldest first" is immediately clear.
    func label(for field: DocumentSortField) -> String {
        switch (field, self) {
        case (.name, .ascending): return "A to Z"
        case (.name, .descending): return "Z to A"
        case (_, .ascending): return "Oldest first"
        case (_, .descending): return "Newest first"
        }
    }
}

struct DocumentSort: Equatable {
    var field: DocumentSortField = .modified
    var direction: SortDirection = .descending

    /// Spoken summary of the current ordering, used as the sort button's
    /// accessibility value so the state is available without opening the menu.
    var spokenDescription: String {
        "\(field.label), \(direction.label(for: field))"
    }

    func sorted(_ documents: [Document]) -> [Document] {
        let ordered = documents.sorted { lhs, rhs in
            switch field {
            case .name:
                // Case- and diacritic-insensitive, and numeric so "note 10"
                // sorts after "note 9" rather than before it.
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            case .created:
                return lhs.created < rhs.created
            case .modified:
                return lhs.modified < rhs.modified
            }
        }
        return direction == .ascending ? ordered : ordered.reversed()
    }
}
