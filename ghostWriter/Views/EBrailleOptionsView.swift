//
//  EBrailleOptionsView.swift
//  ghostWriter
//
//  Collects the facts eBraille requires before an export can be produced.
//
//  Every other share format is derivable from the document alone. eBraille is
//  not: the standard makes a creator, a copyright year, a braille grade, and a
//  completeness declaration mandatory, and none of those can be inferred from
//  markdown. Rather than guess and produce a file that misdescribes itself,
//  this asks.
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
    @State private var copyrightYear: String
    @State private var isCompleteTranscription: Bool
    @FocusState private var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Text in a field lines up with the row it sits in: trailing beside its
    /// label, leading when stacked beneath it.
    private var fieldAlignment: TextAlignment {
        dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
    }

    private enum Field {
        case creator
        case copyrightYear
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
        _copyrightYear = State(initialValue: settings.eBrailleCopyrightYear)
        _isCompleteTranscription = State(
            initialValue: settings.eBrailleCompleteTranscription
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Converts your file to the eBraille 1.0 standard.")
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

                    LabeledContent("Copyright Year") {
                        TextField("", text: $copyrightYear)
                            .focused($focusedField, equals: .copyrightYear)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(fieldAlignment)
                    }
                } footer: {
                    Text("The eBraille standard requires an author and a copyright year. Left empty, the author is recorded as ghostWriter Markdown and the year as the current one.")
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
                    // Read-only: ghostWriter produced the file, so this is a
                    // statement of fact rather than something to choose.
                    LabeledContent("Producer", value: EBrailleMetadata.producer)
                } footer: {
                    Text("Recorded in the file to identify the software that produced it.")
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
        settings.eBrailleCopyrightYear = copyrightYear
        settings.eBrailleCompleteTranscription = isCompleteTranscription

        onExport(
            EBrailleMetadata(
                creator: creator,
                grade: grade,
                copyrightYear: copyrightYear,
                isCompleteTranscription: isCompleteTranscription
            )
        )
    }
}
