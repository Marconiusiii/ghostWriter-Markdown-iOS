//
//  NewDocumentView.swift
//  ghostWriter
//
//  Asks for a filename before creating a document.
//
//  This replaces deriving the name from the first line of the text. That was
//  clever and it was wrong: the name changed as you typed, a half-finished
//  heading produced a nonsense filename, and there was never a clear moment
//  when the document became "yours". Asking once is plainer and predictable.
//

import SwiftUI

struct NewDocumentView: View {
    /// Called with the chosen name once the user confirms.
    let onCreate: (String) -> Void

    @State private var name = ""
    @FocusState private var nameFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Text in a field lines up with the row it sits in: trailing beside its
    /// label, leading when stacked beneath it.
    private var fieldAlignment: TextAlignment {
        dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The name was previously announced through an
                    // accessibilityLabel with nothing on screen to match it,
                    // so the field was unlabelled to anyone looking at it.
                    // LabeledContent makes the label visible and permanent,
                    // and is the field's only accessible name.
                    LabeledContent("Document Name") {
                        TextField("", text: $name)
                            .focused($nameFieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .multilineTextAlignment(fieldAlignment)
                            .onSubmit(create)
                    }
                } footer: {
                    Text("The document is saved as a markdown file with this name. You can rename it later from File Actions.")
                }

                Section {
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .labeledContentStyle(ReflowingLabeledContentStyle())
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") { nameFieldFocused = false }
                        .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        onCreate(trimmedName)
        dismiss()
    }
}
