//
//  BRFOptionsView.swift
//  ghostWriter
//
//  Collects the page geometry a BRF export needs.
//
//  BRF stores finished braille pages: the line width and page depth are written
//  into the file and cannot be changed by whatever reads it. A file wrapped for
//  40 cells reads badly on a 32-cell display, so these are asked rather than
//  assumed. The braille grade is asked for the same reason it is for eBraille.
//
//  Nothing else applies. BRF has no metadata container, so an author, a
//  copyright year, and a transcription declaration would be collected and then
//  discarded.
//

import SwiftUI

struct BRFOptionsView: View {
    @Environment(AppSettings.self) private var settings

    let onCancel: () -> Void
    let onExport: (BRFExportOptions) -> Void

    @State private var grade: BrailleGrade
    @State private var cellsPerLine: Int
    @State private var linesPerPage: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Widths and depths real braille hardware uses.
    private static let cellChoices = [20, 24, 27, 30, 32, 34, 38, 40, 42]
    private static let lineChoices = [6, 8, 10, 20, 24, 25, 26, 28, 30]

    init(
        settings: AppSettings,
        onCancel: @escaping () -> Void,
        onExport: @escaping (BRFExportOptions) -> Void
    ) {
        self.onCancel = onCancel
        self.onExport = onExport
        _grade = State(initialValue: settings.eBrailleGrade)
        _cellsPerLine = State(initialValue: settings.brfCellsPerLine)
        _linesPerPage = State(initialValue: settings.brfLinesPerPage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                    LabeledContent("Cells Per Line") {
                        Picker(selection: $cellsPerLine) {
                            ForEach(Self.cellChoices, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                    }

                    LabeledContent("Lines Per Page") {
                        Picker(selection: $linesPerPage) {
                            ForEach(Self.lineChoices, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                    }
                } footer: {
                    Text("Match these to your braille display or embosser. The standard braille page is 40 cells by 25 lines.")
                }

                Section {
                    Button("Export and Share…", action: export)
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .labeledContentStyle(ReflowingLabeledContentStyle())
            .navigationTitle("Braille Ready Format")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func export() {
        settings.eBrailleGrade = grade
        settings.brfCellsPerLine = cellsPerLine
        settings.brfLinesPerPage = linesPerPage

        onExport(
            BRFExportOptions(
                grade: grade,
                pageSetup: BRFWriter.PageSetup(
                    cellsPerLine: cellsPerLine,
                    linesPerPage: linesPerPage
                )
            )
        )
    }
}

/// What a BRF export needs: the braille code, and the page it is written for.
nonisolated struct BRFExportOptions: Equatable, Sendable {
    let grade: BrailleGrade
    let pageSetup: BRFWriter.PageSetup
}
