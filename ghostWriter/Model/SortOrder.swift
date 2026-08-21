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
    case lastOpened

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return String(localized: "Name")
        case .created: return String(localized: "Date Created")
        case .modified: return String(localized: "Date Modified")
        case .lastOpened: return String(localized: "Last Opened")
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
        case (.name, .ascending): return String(localized: "A to Z")
        case (.name, .descending): return String(localized: "Z to A")
        case (_, .ascending): return String(localized: "Oldest first")
        case (_, .descending): return String(localized: "Newest first")
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

    func sorted(
        _ documents: [Document],
        metadata: DocumentLibraryMetadataStore? = nil
    ) -> [Document] {
        let pinned = documents.filter {
            metadata?.isPinned($0.url) == true
        }
        let unpinned = documents.filter {
            metadata?.isPinned($0.url) != true
        }
        return sortedGroup(pinned, metadata: metadata)
            + sortedGroup(unpinned, metadata: metadata)
    }

    private func sortedGroup(
        _ documents: [Document],
        metadata: DocumentLibraryMetadataStore?
    ) -> [Document] {
        documents.sorted { lhs, rhs in
            let comparison = compare(lhs, rhs, metadata: metadata)
            if comparison == .orderedSame {
                return lhs.displayName.localizedStandardCompare(rhs.displayName)
                    == .orderedAscending
            }
            return direction == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    private func compare(
        _ lhs: Document,
        _ rhs: Document,
        metadata: DocumentLibraryMetadataStore?
    ) -> ComparisonResult {
        switch field {
        case .name:
            // Case- and diacritic-insensitive, and numeric so "note 10"
            // sorts after "note 9" rather than before it.
            return lhs.displayName.localizedStandardCompare(rhs.displayName)
        case .created:
            return lhs.created.compare(rhs.created)
        case .modified:
            return lhs.modified.compare(rhs.modified)
        case .lastOpened:
            let left = metadata?.lastOpened(lhs.url) ?? .distantPast
            let right = metadata?.lastOpened(rhs.url) ?? .distantPast
            return left.compare(right)
        }
    }
}
