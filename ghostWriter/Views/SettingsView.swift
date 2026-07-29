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
    @AccessibilityFocusState private var focusedElement: FocusTarget?
    @State private var showingHelp = false
    @State private var showingStatusBarSettings = false
    @State private var showingMailComposer = false
    @State private var showingMailUnavailable = false
    @State private var focusRequestGate = FocusRestorationRequestGate()

    private enum FocusTarget: Hashable {
        case indentation
        case theme
        case editorFont
        case customizeStatusBar
        case help
        case feedback
    }

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
                    .pickerStyle(.menu)
                    .accessibilityFocused($focusedElement, equals: .indentation)

                    Toggle("Automatic Lists", isOn: $settings.smartListsEnabled)
                        .accessibilityHint("Continues bullets and numbering when you press return")

                    Toggle(
                        "Keyboard Shortcuts",
                        isOn: $settings.keyboardShortcutsEnabled
                    )
                    .accessibilityHint(
                        "Enables ghostWriter commands for a hardware keyboard"
                    )
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused($focusedElement, equals: .theme)

                    Picker("Editor Font", selection: $settings.editorFontDesign) {
                        ForEach(EditorFontDesign.allCases) { design in
                            Text(design.label).tag(design)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused($focusedElement, equals: .editorFont)
                }

                Section {
                    Toggle("Status Bar", isOn: $settings.statusBarEnabled)
                        .accessibilityHint("Shows selected document information after the editor")

                    if settings.statusBarEnabled {
                        Button("Customize Status Bar") {
                            focusRequestGate.invalidate()
                            showingStatusBarSettings = true
                        }
                        .accessibilityFocused($focusedElement, equals: .customizeStatusBar)
                    }
                } header: {
                    Text("Editor Status")
                } footer: {
                    Text("The status bar is one focus stop beneath the editor and does not interrupt typing.")
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
                    externalLink(
                        title: "ghostWriter on the web",
                        url: "https://marconius.com/fun/ghostWriter/"
                    )
                    externalLink(
                        title: "Privacy Policy",
                        url: "https://marconius.com/gwPrivacy/"
                    )
                    Button("Send Feedback", action: sendFeedback)
                        .accessibilityHint("Opens an in-app email with app and system information included")
                        .accessibilityFocused($focusedElement, equals: .feedback)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Help") {
                        focusRequestGate.invalidate()
                        showingHelp = true
                    }
                    .accessibilityFocused($focusedElement, equals: .help)
                }
            }
        }
        .sheet(isPresented: $showingHelp, onDismiss: {
            restoreFocus(to: .help)
        }) {
            HelpView()
        }
        .sheet(isPresented: $showingStatusBarSettings, onDismiss: {
            restoreFocus(to: .customizeStatusBar)
        }) {
            StatusBarSettingsView()
        }
        .sheet(isPresented: $showingMailComposer, onDismiss: {
            restoreFocus(to: .feedback)
        }) {
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
                restoreFocus(to: .feedback)
            }
            Button("Cancel", role: .cancel) {
                restoreFocus(to: .feedback)
            }
        } message: {
            Text("Mail is not configured on this device. You can copy the feedback address and use it in another mail app.")
        }
        .onChange(of: settings.indentUnit) { _, _ in
            restoreFocus(to: .indentation)
        }
        .onChange(of: settings.appearance) { _, _ in
            restoreFocus(to: .theme)
        }
        .onChange(of: settings.editorFontDesign) { _, _ in
            restoreFocus(to: .editorFont)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: .now)
        return "© \(year) Marco Salsiccia"
    }

    private func sendFeedback() {
        focusRequestGate.invalidate()
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else {
            showingMailUnavailable = true
        }
    }

    private func externalLink(title: String, url: String) -> some View {
        Link(title, destination: URL(string: url)!)
            .accessibilityAddTraits(.isLink)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityHint("Opens in external browser")
    }

    private func restoreFocus(to target: FocusTarget) {
        let requestID = focusRequestGate.begin()
        focusedElement = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard focusRequestGate.permits(requestID) else { return }
            focusedElement = target
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard focusRequestGate.permits(requestID) else { return }
            focusedElement = target
        }
    }
}

private struct StatusBarSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            Form {
                Section("Status Information") {
                    Toggle("Current Line and Column", isOn: $settings.statusShowsLineAndColumn)
                    Toggle("Line Count", isOn: $settings.statusShowsLineCount)
                    Toggle("Word Count", isOn: $settings.statusShowsWordCount)
                    Toggle("Character Count", isOn: $settings.statusShowsCharacterCount)
                    Toggle("Heading Level", isOn: $settings.statusShowsHeadingLevel)
                    Toggle("Selected Word Count", isOn: $settings.statusShowsSelectedWordCount)
                    Toggle(
                        "Selected Character Count",
                        isOn: $settings.statusShowsSelectedCharacterCount
                    )
                }

                Section("Sample Status") {
                    Text(sampleStatus)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Customize Status Bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }

    private var sampleStatus: String {
        let text = "# Sample heading\nA short status bar example."
        let status = DocumentStatus.calculate(
            text: text,
            selection: TextSelection(location: 2, length: 6)
        )
        return status.description(
            options: DocumentStatusOptions(
                lineAndColumn: settings.statusShowsLineAndColumn,
                lineCount: settings.statusShowsLineCount,
                wordCount: settings.statusShowsWordCount,
                characterCount: settings.statusShowsCharacterCount,
                headingLevel: settings.statusShowsHeadingLevel,
                selectedWordCount: settings.statusShowsSelectedWordCount,
                selectedCharacterCount: settings.statusShowsSelectedCharacterCount
            )
        )
    }
}
