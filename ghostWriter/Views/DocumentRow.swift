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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLayout {
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

            if let status = document.availability.statusDescription {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Color.ghostMuted)
            }
        }
        .padding(.vertical, 4)
        // Collapse the row into one element with one coherent sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityLabel: String {
        let pinDescription = isPinned ? "Pinned, " : ""
        let statusDescription = document.availability.statusDescription
            .map { ", \($0)" } ?? ""
        return "\(pinDescription)\(document.displayName), modified \(DateFormatting.spoken(document.modified)), created \(DateFormatting.spoken(document.created))\(statusDescription)"
    }

    private var accessibilityHint: String {
        document.availability.isAvailable
            ? "Opens in the editor"
            : "Downloads this document and opens it when ready"
    }

    private var metadataLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 12))
    }

    private var titleLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 8))
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
    let onMove: () -> Void
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
                "Move",
                systemImage: "folder",
                action: onMove
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
