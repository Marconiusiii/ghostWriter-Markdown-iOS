//
//  PowerPointOptionsView.swift
//  ghostWriter
//
//  The one decision required before a presentation is created.
//

import SwiftUI

struct PowerPointOptionsView: View {
    let settings: AppSettings
    let onCancel: () -> Void
    let onExport: (PowerPointExportOptions) -> Void

    @State private var theme: PowerPointTheme
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?

    private enum AccessibilityTarget: Hashable {
        case theme
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Presentation theme") {
                        Picker(selection: $theme) {
                            ForEach(PowerPointTheme.allCases) { theme in
                                Text(theme.label).tag(theme)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .accessibilityFocused($accessibilityFocus, equals: .theme)
                        .onChange(of: theme) { _, _ in
                            restoreThemeFocusAfterSelection()
                        }
                    }
                }

                Section {
                    Button("Export and share…", action: export)
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .labeledContentStyle(ReflowingLabeledContentStyle())
            .navigationTitle("PowerPoint export")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func export() {
        settings.powerPointTheme = theme
        onExport(PowerPointExportOptions(theme: theme))
    }

    private func restoreThemeFocusAfterSelection() {
        accessibilityFocus = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            accessibilityFocus = .theme
            try? await Task.sleep(for: .milliseconds(350))
            accessibilityFocus = .theme
        }
    }
}
