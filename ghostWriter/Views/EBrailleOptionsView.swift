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
//  confirming rather than retyping.
//
//  The actions sit at the end of the form rather than in the toolbar, so they
//  come last in reading order — after the choices they act on, which is where
//  someone moving through the screen in sequence expects to meet them.
//

import SwiftUI

struct EBrailleOptionsView: View {
    @Environment(AppSettings.self) private var settings

    let documentTitle: String
    let onCancel: () -> Void
    let onExport: (EBrailleMetadata) -> Void

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Text("Converts your file to the eBraille 1.0 standard.")
                }

                Section {
                    Picker("Braille Grade", selection: $settings.eBrailleGrade) {
                        ForEach(BrailleGrade.allCases) { grade in
                            Text(grade.displayName).tag(grade)
                        }
                    }
                }

                Section {
                    TextField("Author", text: $settings.eBrailleCreator)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    TextField("Copyright Year", text: $settings.eBrailleCopyrightYear)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("The eBraille standard requires an author and a copyright year. Left empty, the author is recorded as ghostWriter Markdown and the year as the current one.")
                }

                Section {
                    Toggle(
                        "Complete Transcription",
                        isOn: $settings.eBrailleCompleteTranscription
                    )
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
                    Button("Export and Share…") {
                        onExport(
                            EBrailleMetadata(
                                creator: settings.eBrailleCreator,
                                grade: settings.eBrailleGrade,
                                copyrightYear: settings.eBrailleCopyrightYear,
                                isCompleteTranscription: settings.eBrailleCompleteTranscription
                            )
                        )
                    }
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .navigationTitle("eBraille Export")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
