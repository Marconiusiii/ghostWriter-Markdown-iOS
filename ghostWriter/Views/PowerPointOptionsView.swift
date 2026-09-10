//
//  PowerPointOptionsView.swift
//  ghostWriter
//
//  Presentation theme and font choices before export.
//

import SwiftUI

struct PowerPointOptionsView: View {
    let settings: AppSettings
    let onCancel: () -> Void
    let onExport: (PowerPointExportOptions) -> Void

    @State private var theme: PowerPointTheme
    @State private var font: PowerPointFont

    init(
        settings: AppSettings,
        onCancel: @escaping () -> Void,
        onExport: @escaping (PowerPointExportOptions) -> Void
    ) {
        self.settings = settings
        self.onCancel = onCancel
        self.onExport = onExport
        _theme = State(initialValue: settings.powerPointTheme)
        _font = State(initialValue: settings.powerPointFont)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Presentation theme", selection: $theme) {
                        ForEach(PowerPointTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Font family", selection: $font) {
                        ForEach(PowerPointFont.allCases) { font in
                            Text(verbatim: font.rawValue).tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Export and share…", action: export)
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .navigationTitle("PowerPoint export")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func export() {
        settings.powerPointTheme = theme
        settings.powerPointFont = font
        onExport(PowerPointExportOptions(theme: theme, font: font))
    }
}
