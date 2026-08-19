//
//  NewFolderView.swift
//  ghostWriter
//
//  Names a new folder.
//
//  Not a Form, so the field is labelled by a Text above it rather than by
//  LabeledContent. A placeholder is not a label: it vanishes as soon as there
//  is a value, leaving a field no one can identify afterwards.
//
//  The visible label is hidden from VoiceOver and its text given to the field
//  as the field's own name. Combining the two into one element would risk
//  VoiceOver losing the ability to activate and edit the field, and leaving
//  the label visible to VoiceOver would put a dead stop in front of it. This
//  way there is one element, it is editable, and it is named.
//

import SwiftUI

struct NewFolderView: View {
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                Text(fieldLabel)
                    .font(.subheadline)
                    .accessibilityHidden(true)

                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityLabel(fieldLabel)
            }

            // A row of buttons at an accessibility text size runs out of width
            // and truncates, so the two stack instead.
            buttonLayout {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Create") {
                    onCreate(name)
                    dismiss()
                }
                .ghostProminentButtonStyle()
                .disabled(trimmedName.isEmpty)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.pageBackground)
    }

    /// One string for both the visible label and the field's accessible name,
    /// so the two can never drift apart.
    private let fieldLabel = "Folder Name"

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `AnyLayout` rather than an if/else so the buttons keep their identity
    /// across the switch and do not lose focus as the text size changes.
    @ViewBuilder
    private func buttonLayout(
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            content()
        }
    }
}
