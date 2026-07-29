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
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onRender: () -> Void
    let onShare: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(document.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.ghostText)

                if isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Color.ghostAccent)
                }
            }

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
        .accessibilityAction(
            named: "\(isPinned ? "Unpin" : "Pin") \(document.displayName)",
            onTogglePin
        )
        .accessibilityAction(
            named: "Render \(document.displayName)",
            onRender
        )
        .accessibilityAction(
            named: "Share \(document.displayName)",
            onShare
        )
        .accessibilityAction(
            named: "Rename \(document.displayName)",
            onRename
        )
        .accessibilityAction(
            named: "Duplicate \(document.displayName)",
            onDuplicate
        )
        .accessibilityAction(
            named: "Delete \(document.displayName)",
            onDelete
        )
    }

    private var accessibilityLabel: String {
        let pinDescription = isPinned ? "Pinned, " : ""
        return "\(pinDescription)\(document.displayName), modified \(DateFormatting.spoken(document.modified)), created \(DateFormatting.spoken(document.created))"
    }

    private var metadataLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 12))
    }
}

/// A visible, discoverable counterpart to swipe and custom accessibility
/// actions. It remains in the accessibility hierarchy for Switch Control,
/// Voice Control, keyboard navigation, and VoiceOver. Every accessible name
/// starts with its visible label and ends with the document name.
struct DocumentActionsMenu: View {
    let document: Document
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onRender: () -> Void
    let onShare: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            actionButton(
                isPinned ? "Unpin" : "Pin",
                systemImage: isPinned ? "pin.slash" : "pin",
                action: onTogglePin
            )

            Divider()

            actionButton(
                "Render",
                systemImage: "doc.richtext",
                action: onRender
            )
            actionButton(
                "Share",
                systemImage: "square.and.arrow.up",
                action: onShare
            )
            actionButton(
                "Rename",
                systemImage: "pencil",
                action: onRename
            )
            actionButton(
                "Duplicate",
                systemImage: "doc.on.doc",
                action: onDuplicate
            )
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete \(document.displayName)")
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Actions for \(document.displayName)")
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .accessibilityLabel("\(title) \(document.displayName)")
    }
}
