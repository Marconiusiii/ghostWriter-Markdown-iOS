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
//  BRF has no metadata container. This export creates practical UEB BRF for
//  displays and straightforward embossed pages, not a production transcription.
//

import SwiftUI

struct BRFOptionsView: View {
    @Environment(AppSettings.self) private var settings

    let onCancel: () -> Void
    let onExport: (BRFExportOptions) -> Void

    @State private var grade: BrailleGrade
    @State private var outputPurpose: BRFWriter.OutputPurpose = .brailleDisplay
    @State private var layout: Layout
    @State private var cellsPerLine: Int
    @State private var linesPerPage: Int
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum AccessibilityTarget: Hashable {
        case grade
        case outputPurpose
        case layout
        case cellsPerLine
        case linesPerPage
    }

    private enum Layout: String, CaseIterable, Identifiable {
        case standard
        case custom

        var id: String { rawValue }
        var label: String {
            switch self {
            case .standard: return String(localized: "Standard BRF page (40 by 25)")
            case .custom: return String(localized: "Custom braille page")
            }
        }
    }

    /// Widths and depths real braille hardware uses.
    private static let cellChoices = [20, 24, 27, 30, 32, 34, 38, 40, 42]
    private static let lineChoices = [6, 8, 10, 20, 24, 25, 26, 28, 30]

    init(
        settings: AppSettings,
        documentLanguage: String,
        onCancel: @escaping () -> Void,
        onExport: @escaping (BRFExportOptions) -> Void
    ) {
        self.onCancel = onCancel
        self.onExport = onExport
        _grade = State(initialValue: BrailleGrade.suggested(
            for: documentLanguage,
            englishDefault: settings.eBrailleGrade
        ))
        _layout = State(
            initialValue: settings.brfCellsPerLine == 40
                && settings.brfLinesPerPage == 25 ? .standard : .custom
        )
        _cellsPerLine = State(initialValue: settings.brfCellsPerLine)
        _linesPerPage = State(initialValue: settings.brfLinesPerPage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Braille code") {
                        Picker(selection: $grade) {
                            ForEach(BrailleGrade.allCases) { grade in
                                Text(grade.displayName).tag(grade)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused($accessibilityFocus, equals: .grade)
                        .onChange(of: grade) { _, _ in restoreFocus(to: .grade) }
                    }
                }

                Section {
                    LabeledContent("Use") {
                        Picker(selection: $outputPurpose) {
                            Text("Braille display")
                                .tag(BRFWriter.OutputPurpose.brailleDisplay)
                            Text("Emboss on paper")
                                .tag(BRFWriter.OutputPurpose.embossedPages)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused(
                            $accessibilityFocus,
                            equals: .outputPurpose
                        )
                        .onChange(of: outputPurpose) { _, _ in
                            restoreFocus(to: .outputPurpose)
                        }
                    }
                } footer: {
                    Text("Choose how you plan to use this BRF file. Embossed pages include a braille page number at the bottom of each page.")
                }

                Section {
                    LabeledContent("Layout") {
                        Picker(selection: $layout) {
                            ForEach(Layout.allCases) { layout in
                                Text(layout.label).tag(layout)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused($accessibilityFocus, equals: .layout)
                        .onChange(of: layout) { _, _ in restoreFocus(to: .layout) }
                    }
                } footer: {
                    Text("Standard pages use 40 cells by 25 lines.")
                }

                if layout == .custom {
                    Section {
                    LabeledContent("Cells per line") {
                        Picker(selection: $cellsPerLine) {
                            ForEach(Self.cellChoices, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused($accessibilityFocus, equals: .cellsPerLine)
                        .onChange(of: cellsPerLine) { _, _ in
                            restoreFocus(to: .cellsPerLine)
                        }
                    }

                    LabeledContent("Lines per page") {
                        Picker(selection: $linesPerPage) {
                            ForEach(Self.lineChoices, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused($accessibilityFocus, equals: .linesPerPage)
                        .onChange(of: linesPerPage) { _, _ in
                            restoreFocus(to: .linesPerPage)
                        }
                    }
                    } footer: {
                        if outputPurpose == .brailleDisplay {
                            Text("Match these dimensions to your braille display.")
                        } else {
                            Text("Match these dimensions to the page size used by your embosser. The final line is reserved for the page number.")
                        }
                    }
                }

                Section {
                    Button("Export and share…", action: export)
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
        let pageSetup = layout == .standard
            ? BRFWriter.PageSetup.standard
            : BRFWriter.PageSetup(
                cellsPerLine: cellsPerLine,
                linesPerPage: linesPerPage
            )
        settings.brfCellsPerLine = pageSetup.cellsPerLine
        settings.brfLinesPerPage = pageSetup.linesPerPage

        onExport(
            BRFExportOptions(
                grade: grade,
                pageSetup: pageSetup,
                outputPurpose: outputPurpose
            )
        )
    }

    private func restoreFocus(to target: AccessibilityTarget) {
        accessibilityFocus = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            accessibilityFocus = target
            try? await Task.sleep(for: .milliseconds(350))
            accessibilityFocus = target
        }
    }
}

/// What a BRF export needs: the braille code, and the page it is written for.
nonisolated struct BRFExportOptions: Equatable, Sendable {
    let grade: BrailleGrade
    let pageSetup: BRFWriter.PageSetup
    let outputPurpose: BRFWriter.OutputPurpose
}
