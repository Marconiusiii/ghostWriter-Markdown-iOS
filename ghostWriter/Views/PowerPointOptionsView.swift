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
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?

    private enum AccessibilityTarget: Hashable {
        case theme
        case font
    }

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
                    .accessibilityFocused($accessibilityFocus, equals: .theme)
                    .onChange(of: theme) { _, _ in
                        restoreFocusAfterSelection(to: .theme)
                    }

                    Picker("Font family", selection: $font) {
                        ForEach(PowerPointFont.allCases) { font in
                            Text(verbatim: font.rawValue).tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused($accessibilityFocus, equals: .font)
                    .onChange(of: font) { _, _ in
                        restoreFocusAfterSelection(to: .font)
                    }
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

    private func restoreFocusAfterSelection(to target: AccessibilityTarget) {
        accessibilityFocus = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            accessibilityFocus = target
            try? await Task.sleep(for: .milliseconds(350))
            accessibilityFocus = target
        }
    }
}
