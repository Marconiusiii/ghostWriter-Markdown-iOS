//
//  OutlineView.swift
//  ghostWriter
//
//  The document outline: every heading, at its real level, navigable as a list.
//
//  A plain text field is one flat element to VoiceOver, so a long document has
//  no internal structure to move through. Skimming by heading is trivial when
//  you can see the page and genuinely painful when you cannot. This screen
//  gives that back — and selecting a heading moves the cursor there, so it is a
//  navigation tool rather than just a summary.
//

import SwiftUI

struct OutlineView: View {
    let entries: [OutlineEntry]
    /// Called with the character offset of the chosen heading.
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    outlineList
                }
            }
            .navigationTitle("Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var outlineList: some View {
        List(entries) { entry in
            Button {
                onSelect(entry.characterOffset)
                dismiss()
            } label: {
                HStack(spacing: 0) {
                    // Visual indentation communicates depth to sighted readers.
                    // The heading trait below carries the same information to
                    // VoiceOver, so neither audience depends on the other's cue.
                    if entry.level > 1 {
                        Spacer()
                            .frame(width: CGFloat(entry.level - 1) * 16)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.spokenLabel)
                            .font(font(for: entry.level))
                            .foregroundStyle(Color.ghostText)
                            .multilineTextAlignment(.leading)

                        Text("Level \(entry.level)")
                            .font(.caption)
                            .foregroundStyle(Color.ghostMuted)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            // One clear label rather than two fragments read in sequence.
            .accessibilityLabel(String(localized: "\(entry.spokenLabel), heading level \(entry.level)"))
            .accessibilityHint("Moves the cursor to this heading")
            .accessibilityAddTraits(.isHeader)
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Headings", systemImage: "list.bullet.indent")
        } description: {
            Text("Add a heading by starting a line with a number sign, like # Introduction.")
        }
    }

    /// Heading size tracks level, but always through a Dynamic Type text style
    /// so it scales with the reader's setting.
    private func font(for level: Int) -> Font {
        switch level {
        case 1: return .headline
        case 2: return .subheadline.weight(.semibold)
        default: return .subheadline
        }
    }
}
