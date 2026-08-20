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
    @State private var attemptedSubmission = false

    private let fieldLabel = "Document name"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(fieldLabel)
                            .font(.subheadline)
                            .accessibilityHidden(true)

                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .accessibilityLabel(fieldLabel)
                            .onSubmit(create)

                        if shouldShowValidationMessage,
                           case .invalid(let message) = validation {
                            Text(message)
                        }
                    }
                } footer: {
                    Text("The .md filename extension is added automatically.")
                }

                Section {
                    Button("Create", action: create)
                        .disabled(!validation.isValid)
                }
            }
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

    private var validation: DocumentStore.DocumentNameValidation {
        DocumentStore.validateDocumentName(name)
    }

    private var shouldShowValidationMessage: Bool {
        attemptedSubmission || !name.isEmpty
    }

    private func create() {
        attemptedSubmission = true
        guard case .valid(let normalizedName) = validation else { return }
        onCreate(normalizedName)
        dismiss()
    }
}
