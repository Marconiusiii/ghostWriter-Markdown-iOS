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
//  transcriber working from a published book has somewhere to record what they
//  are transcribing and under what terms.
//
//  Author and transcriber are deliberately two fields. eBraille reserves
//  `dc:creator` for the author of the original work and `a11y:producer` for
//  whoever produced the braille; collapsing them into one "Author" box meant
//  every transcription of someone else's book named the wrong person.
//
//  Answers are remembered in settings, so a second export is a matter of
//  confirming rather than retyping. The fields edit local state rather than
//  settings directly: binding a text field straight to AppSettings wrote to
//  UserDefaults and republished the whole settings object on every keystroke,
//  which redrew every view observing any setting — including the editor behind
//  this sheet — and made typing lag. Settings are written once, on export.
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
    @Environment(AppSettings.self) private var settings

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    /// value that is not one of those gets corrected on the way out. Saying so
    /// here means the correction is visible before the file is written rather
    /// than discovered afterwards by a validator.
    private var copyrightNote: String? {
        let trimmed = copyrightYear.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let normalized = EBrailleMetadata.normalizedCopyrightDate(trimmed) else {
            let year = String(Calendar.current.component(.year, from: Date()))
            return "That is not a date the standard allows, so the file will record \(year). Use a year, a year and month, or a full date."
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
        _grade = State(initialValue: settings.eBrailleGrade)
        _creator = State(initialValue: settings.eBrailleCreator)
        _transcriber = State(initialValue: settings.eBrailleTranscriber)
        _copyrightYear = State(initialValue: settings.eBrailleCopyrightYear)
        _isCompleteTranscription = State(
            initialValue: settings.eBrailleCompleteTranscription
        )
        _source = State(initialValue: settings.eBrailleSource)
        _publisher = State(initialValue: settings.eBraillePublisher)
        _rights = State(initialValue: settings.eBrailleRights)
        _subject = State(initialValue: settings.eBrailleSubject)
        _descriptionText = State(initialValue: settings.eBrailleDescription)
        _educationLevel = State(initialValue: settings.eBrailleEducationLevel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Converts your file to the eBraille 1.0 standard.")
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
                    LabeledContent("Braille Grade") {
                        Picker(selection: $grade) {
                            ForEach(BrailleGrade.allCases) { grade in
                                Text(grade.displayName).tag(grade)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
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
                    Text("Who wrote the original work. Left empty, the file records the author as Unknown.")
                }

                Section {
                    LabeledContent("Transcriber") {
                        TextField("", text: $transcriber)
                            .focused($focusedField, equals: .transcriber)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(fieldAlignment)
                    }
                } footer: {
                    Text("You or your agency, if you are transcribing someone else's work. ghostWriter Markdown is always recorded alongside this as the producing software.")
                }

                Section {
                    LabeledContent("Copyright Date") {
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
                        Text("A year, a year and month, or a full date — such as 2026, 2026-04, or 2026-04-17. Left empty, the file records the current year.")
                    }
                }

                Section {
                    // A switch is a fixed width no matter the type size, so at
                    // accessibility sizes it leaves the label a sliver of the
                    // row. The style below gives the label the full width.
                    LabeledContent("Complete Transcription") {
                        Toggle(isOn: $isCompleteTranscription) {
                            EmptyView()
                        }
                    }
                } footer: {
                    Text("Turn this off if the document is only part of a larger work, such as a single chapter.")
                }

                Section {
                    LabeledContent("Source Work") {
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

                    LabeledContent("Education Level") {
                        TextField("", text: $educationLevel)
                            .focused($focusedField, equals: .educationLevel)
                            .multilineTextAlignment(fieldAlignment)
                    }
                } header: {
                    Text("Recommended Details")
                } footer: {
                    Text("The standard recommends these. Any you leave empty are left out of the file. Source Work identifies the book or document being transcribed, and Education Level records the grade or year the material was produced for.")
                }

                Section {
                    Button("Export and Share…", action: export)
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .labeledContentStyle(ReflowingLabeledContentStyle())
            .navigationTitle("eBraille Export")
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

    /// Remembers the answers for next time, then hands them to the writer.
    private func export() {
        focusedField = nil

        settings.eBrailleGrade = grade
        settings.eBrailleCreator = creator
        settings.eBrailleTranscriber = transcriber
        settings.eBrailleCopyrightYear = copyrightYear
        settings.eBrailleCompleteTranscription = isCompleteTranscription
        settings.eBrailleSource = source
        settings.eBraillePublisher = publisher
        settings.eBrailleRights = rights
        settings.eBrailleSubject = subject
        settings.eBrailleDescription = descriptionText
        settings.eBrailleEducationLevel = educationLevel

        onExport(
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
        )
    }
}
