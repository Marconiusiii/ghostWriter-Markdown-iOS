//
//  DocumentRow.swift
//  ghostWriter
//
//  One file in the library. The row is a navigation link that opens the editor,
//  and carries custom accessibility actions for rendering and sharing.
//
//  The accessibility label is written as a single sentence rather than letting
//  three separate Text views be read as disconnected fragments. Hearing
//  "Meeting notes, modified yesterday, created 3 March" is far better than
//  "Meeting notes" then "yesterday" then "3 March" with no idea which is which.
//

import SwiftUI

struct DocumentRow: View {
    let document: Document
    let onRender: () -> Void
    let onShare: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.displayName)
                .font(.headline)
                .foregroundStyle(Color.ghostText)

            HStack(spacing: 12) {
                Label(DateFormatting.short(document.modified), systemImage: "pencil")
                Label(DateFormatting.short(document.created), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(Color.ghostMuted)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
        // Collapse the row into one element with one coherent sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens in the editor")
        // The actions you reach with a rotor swipe. These give VoiceOver users
        // the same capabilities that swipe actions give touch users.
        .accessibilityAction(named: "View rendered HTML", onRender)
        .accessibilityAction(named: "Share", onShare)
        .accessibilityAction(named: "Rename", onRename)
        .accessibilityAction(named: "Delete", onDelete)
    }

    private var accessibilityLabel: String {
        "\(document.displayName), modified \(DateFormatting.spoken(document.modified)), created \(DateFormatting.spoken(document.created))"
    }
}
