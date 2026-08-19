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
                    Picker("Braille Grade", selection: $settings.eBrailleGrade) {
                        ForEach(BrailleGrade.allCases) { grade in
                            Text(grade.displayName).tag(grade)
                        }
                    }
                } header: {
                    Text("Braille")
                } footer: {
                    Text("Grade 2 uses contractions and is what most braille readers prefer. Grade 1 spells every word out in full.")
                }

                Section {
                    TextField("Author", text: $settings.eBrailleCreator)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    TextField("Copyright Year", text: $settings.eBrailleCopyrightYear)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Publication")
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
            }
            .navigationTitle("eBraille Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
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
                }
            }
        }
    }
}
