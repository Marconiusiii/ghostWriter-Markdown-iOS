//
//  SettingsView.swift
//  ghostWriter
//
//  App-wide options. Everything here is a native Form control, so each row is
//  announced with its role, current value, and how to change it without any
//  accessibility work on our part.
//

import MessageUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showingHelp = false
    @State private var showingMailComposer = false
    @State private var showingMailUnavailable = false

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

                    Picker("Editor Font", selection: $settings.editorFontDesign) {
                        ForEach(EditorFontDesign.allCases) { design in
                            Text(design.label).tag(design)
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
                    Button("Help") { showingHelp = true }
                    Link("ghostWriter on the web", destination: URL(string: "https://marconius.com/fun/ghostWriter/")!)
                    Button("Send Feedback", action: sendFeedback)
                        .accessibilityHint("Opens an in-app email with app and system information included")
                } header: {
                    Text("About")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your documents are stored in the ghostWriter folder, which you can open in the Files app.")
                        Text(copyright)
                    }
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
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $showingMailComposer) {
            MailComposerView(
                recipient: FeedbackMailDraft.recipient,
                subject: FeedbackMailDraft.subject,
                body: FeedbackMailDraft.currentBody,
                onFinish: { _ in }
            )
        }
        .alert("Mail Is Not Available", isPresented: $showingMailUnavailable) {
            Button("Copy Email Address") {
                UIPasteboard.general.string = FeedbackMailDraft.recipient
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Mail is not configured on this device. You can copy the feedback address and use it in another mail app.")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: .now)
        return "Copyright © \(year) Marco Salsiccia"
    }

    private func sendFeedback() {
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else {
            showingMailUnavailable = true
        }
    }
}
