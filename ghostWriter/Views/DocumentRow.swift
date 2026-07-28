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
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.displayName)
                .font(.headline)
                .foregroundStyle(Color.ghostText)

            metadataLayout {
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
        // The complete set of row actions, declared once. The swipe actions on
        // the list row are deliberately NOT duplicated here — SwiftUI already
        // exposes those to VoiceOver, and declaring the same action in both
        // places is what made every action appear twice.
        .accessibilityAction(named: "View rendered HTML", onRender)
        .accessibilityAction(named: "Share", onShare)
        .accessibilityAction(named: "Rename", onRename)
        .accessibilityAction(named: "Duplicate", onDuplicate)
        .accessibilityAction(named: "Delete", onDelete)
    }

    private var accessibilityLabel: String {
        "\(document.displayName), modified \(DateFormatting.spoken(document.modified)), created \(DateFormatting.spoken(document.created))"
    }

    private var metadataLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 12))
    }
}
