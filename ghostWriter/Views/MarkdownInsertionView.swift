//
//  MarkdownInsertionView.swift
//  ghostWriter
//
//  Native forms for guided Link and external Image insertion.
//

import SwiftUI

enum MarkdownInsertionKind: String, Identifiable {
    case link
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link: return "Insert Link"
        case .image: return "Insert Image"
        }
    }
}

struct MarkdownInsertionView: View {
    let kind: MarkdownInsertionKind
    let initialText: String
    let onInsert: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var descriptiveText: String
    @State private var address = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case descriptiveText
        case address
    }

    init(
        kind: MarkdownInsertionKind,
        initialText: String,
        onInsert: @escaping (String, String) -> Void
    ) {
        self.kind = kind
        self.initialText = initialText
        self.onInsert = onInsert
        _descriptiveText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(descriptiveTextLabel, text: $descriptiveText, axis: .vertical)
                        .focused($focusedField, equals: .descriptiveText)

                    TextField("Address", text: $address)
                        .focused($focusedField, equals: .address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit(insert)
                } footer: {
                    Text(instructions)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert", action: insert)
                        .disabled(!canInsert)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") {
                        focusedField = nil
                    }
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
            .onAppear {
                focusedField = descriptiveText.isEmpty ? .descriptiveText : .address
            }
        }
    }

    private var descriptiveTextLabel: String {
        kind == .link ? "Link text" : "Alternative text"
    }

    private var instructions: String {
        switch kind {
        case .link:
            return "Enter the text readers will encounter and a complete address, including its scheme."
        case .image:
            return "Enter alternative text and the complete web address of the image. Leave alternative text empty only when the image is decorative."
        }
    }

    private var trimmedDescriptiveText: String {
        descriptiveText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validAddress: Bool {
        guard let url = URL(string: trimmedAddress),
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty else {
            return false
        }

        if kind == .image {
            return scheme == "https" || scheme == "http"
        }
        return true
    }

    private var canInsert: Bool {
        validAddress && (kind == .image || !trimmedDescriptiveText.isEmpty)
    }

    private func insert() {
        guard canInsert else { return }
        onInsert(trimmedDescriptiveText, trimmedAddress)
        dismiss()
    }
}
