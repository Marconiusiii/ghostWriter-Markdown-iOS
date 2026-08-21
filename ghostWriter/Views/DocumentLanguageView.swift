//
//  DocumentLanguageView.swift
//  ghostWriter
//
//  A native, per-document language setting used by every export format.
//

import SwiftUI

struct DocumentLanguageView: View {
    let initialTag: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var selection: Selection
    @State private var customTag: String
    @FocusState private var customFieldFocused: Bool
    @AccessibilityFocusState private var languageFocused: Bool

    private enum Selection: Hashable {
        case automatic
        case common(String)
        case custom
    }

    init(
        initialTag: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialTag = initialTag
        self.onSave = onSave
        self.onCancel = onCancel
        let normalized = DocumentLanguage.normalizedTag(initialTag)
        if normalized.isEmpty {
            _selection = State(initialValue: .automatic)
            _customTag = State(initialValue: "")
        } else if DocumentLanguage.commonTags.contains(normalized) {
            _selection = State(initialValue: .common(normalized))
            _customTag = State(initialValue: "")
        } else {
            _selection = State(initialValue: .custom)
            _customTag = State(initialValue: normalized)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Document language") {
                        Picker(selection: $selection) {
                            Text("Automatic (device language)")
                                .tag(Selection.automatic)
                            ForEach(DocumentLanguage.commonTags, id: \.self) { tag in
                                Text(DocumentLanguage.localizedName(for: tag))
                                    .tag(Selection.common(tag))
                            }
                            Text("Other language tag…")
                                .tag(Selection.custom)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused($languageFocused)
                        .onChange(of: selection) { _, newValue in
                            if newValue == .custom {
                                Task { @MainActor in customFieldFocused = true }
                            }
                            restoreLanguageFocus()
                        }
                    }

                    if selection == .custom {
                        LabeledContent("Language tag") {
                            TextField("es-MX", text: $customTag)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($customFieldFocused)
                        }
                    }
                } footer: {
                    Text("This setting describes the document, not the app interface. It is added to exports that support language metadata. Enter a BCP 47 tag, such as es-MX, for a language or regional form not listed.")
                }

                Section {
                    Button("Save", action: save)
                        .disabled(selection == .custom && normalizedCustomTag.isEmpty)
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .labeledContentStyle(ReflowingLabeledContentStyle())
            .navigationTitle("Document language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") { customFieldFocused = false }
                        .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
    }

    private var normalizedCustomTag: String {
        DocumentLanguage.normalizedTag(customTag)
    }

    private func save() {
        switch selection {
        case .automatic:
            onSave(DocumentLanguage.automatic)
        case .common(let tag):
            onSave(tag)
        case .custom:
            onSave(normalizedCustomTag)
        }
    }

    private func restoreLanguageFocus() {
        languageFocused = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            languageFocused = true
            try? await Task.sleep(for: .milliseconds(350))
            languageFocused = true
        }
    }
}
