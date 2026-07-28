//
//  SettingsView.swift
//  ghostWriter
//
//  App-wide options. Everything here is a native Form control, so each row is
//  announced with its role, current value, and how to change it without any
//  accessibility work on our part.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            Form {
                Section("Editing") {
                    Picker("Indentation", selection: $settings.indentUnit) {
                        ForEach(IndentUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }

                    Toggle("Automatic Lists", isOn: $settings.smartListsEnabled)
                        .accessibilityHint("Continues bullets and numbering when you press return")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section {
                    Toggle("Render Sound", isOn: $settings.renderSoundEnabled)
                        .accessibilityHint("Plays a tone when a document is rendered")
                } header: {
                    Text("Sound")
                } footer: {
                    Text("The render sound follows your device's silent switch.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    Link("ghostWriter on the web", destination: URL(string: "https://marconius.com/fun/ghostWriter/")!)
                    Link("Send feedback", destination: URL(string: "mailto:marco@marconius.com?subject=ghostWriter%20Markdown%20Feedback")!)
                } header: {
                    Text("About")
                } footer: {
                    Text("Your documents are stored in the ghostWriter folder, which you can open in the Files app.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
