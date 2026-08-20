//
//  MarkdownInsertionView.swift
//  ghostWriter
//
//  Native forms for guided Link and external Image insertion.
//

import SwiftUI
import UniformTypeIdentifiers

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

struct TactileGraphicInsertionView: View {
    let documentURL: URL
    let onInsert: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var descriptionText = ""
    @State private var selectedFile: URL?
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var failureMessage: String?
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Description") {
                        TextField("", text: $descriptionText, axis: .vertical)
                            .focused($descriptionFocused)
                    }
                } footer: {
                    Text("Briefly identify the tactile graphic and the information it presents. This description is used when the graphic cannot be displayed.")
                }

                Section {
                    LabeledContent("File", value: selectedFile?.lastPathComponent ?? "None selected")
                    Button(selectedFile == nil ? "Choose file…" : "Choose another file…") {
                        showingImporter = true
                    }
                } footer: {
                    Text("Choose an SVG, PNG, or JPG file that was prepared for tactile presentation.")
                }

                Section {
                    Button(isImporting ? "Attaching…" : "Attach and insert", action: insert)
                        .disabled(!canInsert || isImporting)
                }
            }
            .navigationTitle("Tactile Graphic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") { descriptionFocused = false }
                        .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.svg, .png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls): selectedFile = urls.first
            case .failure(let error): failureMessage = error.localizedDescription
            }
        }
        .alert("Could Not Attach Tactile Graphic", isPresented: failureBinding) {
            Button("OK") { failureMessage = nil }
        } message: {
            Text(failureMessage ?? "The selected file could not be attached.")
        }
    }

    private var trimmedDescription: String {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canInsert: Bool {
        selectedFile != nil && !trimmedDescription.isEmpty
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: { failureMessage != nil },
            set: { if !$0 { failureMessage = nil } }
        )
    }

    private func insert() {
        guard canInsert, let source = selectedFile else { return }
        descriptionFocused = false
        isImporting = true
        let description = trimmedDescription
        let accessed = source.startAccessingSecurityScopedResource()

        Task {
            defer {
                if accessed { source.stopAccessingSecurityScopedResource() }
            }
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let data = try Data(contentsOf: source)
                    return try DocumentAssets.importAsset(
                        data: data,
                        originalFileName: source.lastPathComponent,
                        beside: documentURL
                    )
                }
            }.value

            isImporting = false
            switch result {
            case .success(let relativePath):
                onInsert(description, relativePath)
                dismiss()
            case .failure(let error):
                failureMessage = error.localizedDescription
            }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Text in a field lines up with the row it sits in: trailing beside its
    /// label, leading when stacked beneath it.
    private var fieldAlignment: TextAlignment {
        dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
    }

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
                    // LabeledContent rather than a placeholder: a placeholder
                    // disappears as soon as there is a value, leaving a field
                    // no one can identify afterwards. The label is visible for
                    // good and is the row's only accessible name, so the
                    // fields themselves pass no label of their own.
                    LabeledContent(descriptiveTextLabel) {
                        TextField("", text: $descriptiveText, axis: .vertical)
                            .focused($focusedField, equals: .descriptiveText)
                            .multilineTextAlignment(fieldAlignment)
                    }

                    LabeledContent("Address") {
                        TextField("", text: $address)
                            .focused($focusedField, equals: .address)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .multilineTextAlignment(fieldAlignment)
                            .onSubmit(insert)
                    }
                } footer: {
                    Text(instructions)
                }

                Section {
                    Button("Insert", action: insert)
                        .disabled(!canInsert)
                }
            }
            .labeledContentStyle(ReflowingLabeledContentStyle())
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") {
                        focusedField = nil
                    }
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
    }

    private var descriptiveTextLabel: String {
        kind == .link ? "Link text" : "Alternative text"
    }

    private var instructions: String {
        switch kind {
        case .link:
            return "Enter the link text and full address, such as https://example.com."
        case .image:
            return "Enter alternative text and the full image address, such as https://example.com/photo.jpg. Leave alternative text empty only when the image is decorative."
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
