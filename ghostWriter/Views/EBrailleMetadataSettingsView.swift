//
//  EBrailleMetadataSettingsView.swift
//  ghostWriter
//
//  Saved values used to fill in each new eBraille export.
//

import SwiftUI

struct EBrailleMetadataSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?

    private enum AccessibilityTarget: Hashable {
        case grade
    }

    private enum Field: Hashable {
        case creator
        case transcriber
        case copyrightDate
        case source
        case publisher
        case rights
        case subject
        case description
        case educationLevel
    }

    private var fieldAlignment: TextAlignment {
        dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
    }

    private var copyrightNote: String {
        let entered = settings.eBrailleCopyrightDate.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !entered.isEmpty else {
            return "Enter a year, a year and month, or a full date."
        }
        guard let normalized = EBrailleMetadata.normalizedCopyrightDate(entered) else {
            return "Enter a year, a year and month, or a full date."
        }
        guard normalized != entered else {
            return "Used as the copyright date in new exports."
        }
        return "New exports will use \(normalized)."
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LabeledContent("Braille grade") {
                    Picker(selection: $settings.eBrailleGrade) {
                        ForEach(BrailleGrade.allCases) { grade in
                            Text(grade.displayName).tag(grade)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused($accessibilityFocus, equals: .grade)
                    .onChange(of: settings.eBrailleGrade) { _, _ in
                        restoreGradeFocusAfterSelection()
                    }
                }
            }

            Section {
                LabeledContent("Author") {
                    TextField("", text: $settings.eBrailleCreator)
                        .focused($focusedField, equals: .creator)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(fieldAlignment)
                }

                LabeledContent("Produced by") {
                    TextField("", text: $settings.eBrailleTranscriber)
                        .focused($focusedField, equals: .transcriber)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(fieldAlignment)
                }

                LabeledContent("Copyright date") {
                    TextField("", text: $settings.eBrailleCopyrightDate)
                        .focused($focusedField, equals: .copyrightDate)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(fieldAlignment)
                }

                Toggle(
                    "Complete document",
                    isOn: $settings.eBrailleIsCompleteDocument
                )
                .ghostFilledControlTint()
            } footer: {
                Text(copyrightNote)
            }

            Section {
                LabeledContent("Source work") {
                    TextField("", text: $settings.eBrailleSource)
                        .focused($focusedField, equals: .source)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(fieldAlignment)
                }

                LabeledContent("Publisher") {
                    TextField("", text: $settings.eBraillePublisher)
                        .focused($focusedField, equals: .publisher)
                        .textInputAutocapitalization(.words)
                        .multilineTextAlignment(fieldAlignment)
                }

                LabeledContent("Rights") {
                    TextField("", text: $settings.eBrailleRights)
                        .focused($focusedField, equals: .rights)
                        .multilineTextAlignment(fieldAlignment)
                }

                LabeledContent("Subject") {
                    TextField("", text: $settings.eBrailleSubject)
                        .focused($focusedField, equals: .subject)
                        .multilineTextAlignment(fieldAlignment)
                }

                LabeledContent("Description") {
                    TextField(
                        "",
                        text: $settings.eBrailleDescription,
                        axis: .vertical
                    )
                    .focused($focusedField, equals: .description)
                    .lineLimit(1...4)
                    .multilineTextAlignment(fieldAlignment)
                }

                LabeledContent("Education level") {
                    TextField("", text: $settings.eBrailleEducationLevel)
                        .focused($focusedField, equals: .educationLevel)
                        .multilineTextAlignment(fieldAlignment)
                }
            }
        }
        .labeledContentStyle(ReflowingLabeledContentStyle())
        .navigationTitle("eBraille metadata")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Dismiss") { focusedField = nil }
                    .accessibilityLabel("Dismiss keyboard")
            }
        }
    }

    private func restoreGradeFocusAfterSelection() {
        accessibilityFocus = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            accessibilityFocus = .grade
            try? await Task.sleep(for: .milliseconds(350))
            accessibilityFocus = .grade
        }
    }
}
