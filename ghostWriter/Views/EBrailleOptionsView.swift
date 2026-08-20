//
//  EBrailleOptionsView.swift
//  ghostWriter
//
//  Collects the facts eBraille requires before an export can be produced.
//
//  Every other share format is derivable from the document alone. eBraille is
//  not: the standard makes a creator, a producer, a copyright date, a braille
//  grade, and a completeness declaration mandatory, and none of those can be
//  inferred from markdown. Rather than guess and produce a file that
//  misdescribes itself, this asks.
//
//  The standard also marks six properties RECOMMENDED — the source work, the
//  publisher, the rights, the subject, a description, and the education level.
//  Those sit in their own section below the required ones, so the short path
//  stays short for someone exporting a document they wrote themselves, while a
//  producer working from a published book has somewhere to record the source
//  work and the terms under which the braille edition is being shared.
//
//  Author and producer are deliberately two fields. eBraille reserves
//  `dc:creator` for the author of the original work and `a11y:producer` for
//  whoever produced the braille; collapsing them into one "Author" box meant
//  every braille edition of someone else's book named the wrong person.
//
//  Settings supplies initial values. Changes made here apply only to this
//  export, so a one-time edit does not replace the saved defaults.
//
//  The actions sit at the end of the form rather than in the toolbar, so they
//  come last in reading order — after the choices they act on, which is where
//  someone moving through the screen in sequence expects to meet them.
//
//  Every control here is labelled with LabeledContent. A placeholder is not a
//  label: it vanishes the moment there is a value, leaving a field no one can
//  identify afterwards. LabeledContent renders the label visibly, keeps it out
//  of the VoiceOver focus order as a stop of its own, and still folds it into
//  what the control announces — so the label is heard once, with the control,
//  rather than sitting in front of it as dead text to swipe past.
//
//  The wrapped controls carry no label of their own. Naming a control that is
//  already inside a LabeledContent names the row twice, and VoiceOver reads
//  both — `labelsHidden()` does not prevent this, because it only hides a
//  label on screen while leaving it as the control's accessibility name. The
//  label belongs to the LabeledContent and nowhere else.
//

import SwiftUI

struct EBrailleOptionsView: View {
    let documentTitle: String
    let onCancel: () -> Void
    let onExport: (EBrailleMetadata) -> Void

    @State private var grade: BrailleGrade
    @State private var creator: String
    @State private var transcriber: String
    @State private var copyrightYear: String
    @State private var isCompleteTranscription: Bool
    @State private var source: String
    @State private var publisher: String
    @State private var rights: String
    @State private var subject: String
    @State private var descriptionText: String
    @State private var educationLevel: String
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum AccessibilityTarget: Hashable {
        case grade
    }

    /// Text in a field lines up with the row it sits in: trailing beside its
    /// label, leading when stacked beneath it.
    private var fieldAlignment: TextAlignment {
        dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
    }

    private enum Field {
        case creator
        case transcriber
        case copyrightYear
        case source
        case publisher
        case rights
        case subject
        case descriptionText
        case educationLevel
    }

    /// What the copyright date will actually become in the file.
    ///
    /// The spec allows only `YYYY`, `YYYY-MM`, or `YYYY-MM-DD`, so a typed
    private var copyrightNote: String? {
        let trimmed = copyrightYear.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let normalized = EBrailleMetadata.normalizedCopyrightDate(trimmed) else {
            return "Enter a year, a year and month, or a full date."
        }
        guard normalized != trimmed else { return nil }
        return "The file will record this as \(normalized)."
    }

    init(
        settings: AppSettings,
        documentTitle: String,
        onCancel: @escaping () -> Void,
        onExport: @escaping (EBrailleMetadata) -> Void
    ) {
        self.documentTitle = documentTitle
        self.onCancel = onCancel
        self.onExport = onExport
        let defaults = settings.eBrailleMetadataDefaults
        _grade = State(initialValue: defaults.grade)
        _creator = State(initialValue: defaults.creator)
        _transcriber = State(initialValue: defaults.transcriber)
        _copyrightYear = State(initialValue: defaults.copyrightYear)
        _isCompleteTranscription = State(
            initialValue: defaults.isCompleteTranscription
        )
        _source = State(initialValue: defaults.source)
        _publisher = State(initialValue: defaults.publisher)
        _rights = State(initialValue: defaults.rights)
        _subject = State(initialValue: defaults.subject)
        _descriptionText = State(initialValue: defaults.descriptionText)
        _educationLevel = State(initialValue: defaults.educationLevel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Creates a reflowable Unified English Braille document using the eBraille 1.0 format.")
                }

                // The title is not editable here — it comes from the document
                // and is what every other export uses — but it is written to
                // the file as dc:title, so it is shown rather than left as a
                // silent decision.
                Section {
                    LabeledContent("Title", value: documentTitle)
                } footer: {
                    Text("Taken from your document. Rename the document to change it.")
                }

                Section {
                    // The grade names are long enough that label and value
                    // cannot share a row at accessibility sizes without the
                    // value truncating — and "(contracted)" versus
                    // "(uncontracted)" is the entire distinction being made,
                    // so it is the one word that must not be cut off.
                    LabeledContent("Braille grade") {
                        Picker(selection: $grade) {
                            ForEach(BrailleGrade.allCases) { grade in
                                Text(grade.displayName).tag(grade)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused($accessibilityFocus, equals: .grade)
                        .onChange(of: grade) { _, _ in
                            restoreGradeFocusAfterSelection()
                        }
                    }
                }

                Section {
                    LabeledContent("Author") {
                        TextField("", text: $creator)
                            .focused($focusedField, equals: .creator)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(fieldAlignment)
                    }
                } footer: {
                    Text("Who wrote the original work. If the author is not known, enter Unknown.")
                }

                Section {
                    LabeledContent("Produced by") {
                        TextField("", text: $transcriber)
                            .focused($focusedField, equals: .transcriber)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(fieldAlignment)
                    }
                } footer: {
                    Text("The person or organization creating and sharing this braille edition.")
                }

                Section {
                    LabeledContent("Copyright date") {
                        TextField("", text: $copyrightYear)
                            .focused($focusedField, equals: .copyrightYear)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(fieldAlignment)
                    }
                } footer: {
                    // The note replaces the general guidance once there is
                    // something specific to say, rather than adding a second
                    // paragraph to read past.
                    if let copyrightNote {
                        Text(copyrightNote)
                    } else {
                        Text("Required. Enter a year, a year and month, or a full date, such as 2026, 2026-04, or 2026-04-17.")
                    }
                }

                Section {
                    // A switch is a fixed width no matter the type size, so at
                    // accessibility sizes it leaves the label a sliver of the
                    // row. The style below gives the label the full width.
                    LabeledContent("Complete document") {
                        Toggle(isOn: $isCompleteTranscription) {
                            EmptyView()
                        }
                    }
                } footer: {
                    Text("Turn this off if the document is only part of a larger work, such as a single chapter.")
                }

                Section {
                    LabeledContent("Source work") {
                        TextField("", text: $source)
                            .focused($focusedField, equals: .source)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(fieldAlignment)
                    }

                    LabeledContent("Publisher") {
                        TextField("", text: $publisher)
                            .focused($focusedField, equals: .publisher)
                            .textInputAutocapitalization(.words)
                            .multilineTextAlignment(fieldAlignment)
                    }

                    LabeledContent("Rights") {
                        TextField("", text: $rights)
                            .focused($focusedField, equals: .rights)
                            .multilineTextAlignment(fieldAlignment)
                    }

                    LabeledContent("Subject") {
                        TextField("", text: $subject)
                            .focused($focusedField, equals: .subject)
                            .multilineTextAlignment(fieldAlignment)
                    }

                    LabeledContent("Description") {
                        TextField("", text: $descriptionText, axis: .vertical)
                            .focused($focusedField, equals: .descriptionText)
                            .lineLimit(1...4)
                            .multilineTextAlignment(fieldAlignment)
                    }

                    LabeledContent("Education level") {
                        TextField("", text: $educationLevel)
                            .focused($focusedField, equals: .educationLevel)
                            .multilineTextAlignment(fieldAlignment)
                    }
                } header: {
                    Text("Recommended details")
                } footer: {
                    Text("The standard recommends these. Any you leave empty are left out of the file. Source Work identifies an original publication when this document comes from one. Publisher identifies who publishes this eBraille edition.")
                }

                Section {
                    Button("Export and share…", action: export)
                        .disabled(metadata.validationMessage != nil)
                    Button("Cancel", role: .cancel, action: onCancel)
                } footer: {
                    if let message = metadata.validationMessage {
                        Text(message)
                    }
                }
            }
            .labeledContentStyle(ReflowingLabeledContentStyle())
            .navigationTitle("eBraille export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") { focusedField = nil }
                        .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
    }

    private func export() {
        focusedField = nil
        onExport(metadata)
    }

    private var metadata: EBrailleMetadata {
        EBrailleMetadata(
            creator: creator,
            transcriber: transcriber,
            grade: grade,
            copyrightYear: copyrightYear,
            isCompleteTranscription: isCompleteTranscription,
            source: source,
            publisher: publisher,
            rights: rights,
            subject: subject,
            descriptionText: descriptionText,
            educationLevel: educationLevel
        )
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
