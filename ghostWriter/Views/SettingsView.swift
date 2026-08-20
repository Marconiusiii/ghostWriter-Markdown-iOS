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
    @Environment(DocumentStorage.self) private var storage
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var libraryMetadata
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusedElement: FocusTarget?
    @State private var showingHelp = false
    @State private var showingWhyGhostWriter = false
    @State private var showingAcknowledgements = false
    @State private var showingStatusBarSettings = false
    @State private var showingMailComposer = false
    @State private var showingMailUnavailable = false
    @State private var requestedStorageLocation: DocumentStorageChoice?
    @State private var focusRequestGate = FocusRestorationRequestGate()

    private enum FocusTarget: Hashable {
        case indentation
        case documentStorage
        case appLaunch
        case newDocumentCreation
        case theme
        case editorFont
        case customizeStatusBar
        case help
        case whyGhostWriter
        case acknowledgements
        case feedback
    }

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            Form {
                Section {
                    Picker(
                        "Document Storage",
                        selection: documentStorageBinding
                    ) {
                        ForEach(DocumentStorageChoice.allCases) { location in
                            Text(location.label).tag(location)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .documentStorage
                    )
                } header: {
                    Text("Files")
                } footer: {
                    Text(storage.statusDescription)
                }

                Section {
                    Picker(
                        "When App Opens",
                        selection: $settings.appLaunchBehavior
                    ) {
                        ForEach(AppLaunchBehavior.allCases) { behavior in
                            Text(behavior.label).tag(behavior)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .appLaunch
                    )
                } header: {
                    Text("App Launch")
                } footer: {
                    Text("Start a New Document follows your New Documents setting. Open Last Document returns to the most recently opened file when it is still available.")
                }

                Section {
                    Picker(
                        "When Starting a New Document",
                        selection: $settings.newDocumentCreationMode
                    ) {
                        ForEach(NewDocumentCreationMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .newDocumentCreation
                    )
                } header: {
                    Text("New Documents")
                } footer: {
                    Text("Ask for a Title opens the naming screen. Use Today’s Date creates and opens the document immediately. You can rename it later from File Actions.")
                }

                Section("Editing") {
                    Picker("Indentation", selection: $settings.indentUnit) {
                        ForEach(IndentUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityFocused($focusedElement, equals: .indentation)

                    Toggle("Automatic Lists", isOn: $settings.smartListsEnabled)
                        .ghostFilledControlTint()
                        .accessibilityHint("Continues bullets and numbering when you press return")

                    Toggle(
                        "Keyboard Shortcuts",
                        isOn: $settings.keyboardShortcutsEnabled
                    )
                    .ghostFilledControlTint()
                    .accessibilityHint(
                        "Enables ghostWriter commands for a hardware keyboard"
                    )
                }

                Section("VoiceOver Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verbosity")
                            .font(.headline)
                            .accessibilityHidden(true)

                        Picker(
                            "Verbosity",
                            selection: $settings.voiceOverVerbosity
                        ) {
                            ForEach(VoiceOverVerbosity.allCases) { verbosity in
                                Text(verbosity.label).tag(verbosity)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Verbosity")

                    Text(settings.voiceOverVerbosity.description)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "Heading Swipe Navigation",
                            isOn: $settings.headingSwipeNavigationEnabled
                        )
                        .ghostFilledControlTint()

                        Text(
                            "Moves between headings with three-finger horizontal swipes in the editor."
                        )
                    }
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
                        .ghostFilledControlTint()
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
                        .ghostFilledControlTint()
                        .accessibilityHint("Plays a tone when a document is rendered")
                } header: {
                    Text("Sound")
                } footer: {
                    Text("The render sound follows your device's silent switch.")
                }

                Section {
                    NavigationLink("Edit defaults") {
                        EBrailleMetadataSettingsView()
                    }
                } header: {
                    Text("eBraille metadata")
                } footer: {
                    Text("Fills in new eBraille exports. You can edit these values before sharing.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    Button("Why ghostWriter?") {
                        focusRequestGate.invalidate()
                        showingWhyGhostWriter = true
                    }
                    .accessibilityHint("Opens the lore of ghostWriter")
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .whyGhostWriter
                    )
                    Button("Acknowledgements") {
                        focusRequestGate.invalidate()
                        showingAcknowledgements = true
                    }
                    .accessibilityHint("Opens software acknowledgements and licenses")
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .acknowledgements
                    )
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
        .sheet(item: $requestedStorageLocation, onDismiss: {
            restoreFocus(to: .documentStorage)
        }) { destination in
            ICloudMigrationView(
                destination: destination,
                onCompletion: {
                    restoreFocus(to: .documentStorage)
                }
            )
            .environment(storage)
            .environment(store)
            .environment(libraryMetadata)
        }
        .sheet(isPresented: $showingWhyGhostWriter, onDismiss: {
            restoreFocus(to: .whyGhostWriter)
        }) {
            WhyGhostWriterView()
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingAcknowledgements, onDismiss: {
            restoreFocus(to: .acknowledgements)
        }) {
            AcknowledgementsView()
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
        .onChange(of: settings.appLaunchBehavior) { _, _ in
            restoreFocus(to: .appLaunch)
        }
        .onChange(of: settings.newDocumentCreationMode) { _, _ in
            restoreFocus(to: .newDocumentCreation)
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

    private var documentStorageBinding: Binding<DocumentStorageChoice> {
        Binding(
            get: { storage.selectedLocation },
            set: { location in
                guard location != storage.selectedLocation else { return }
                focusRequestGate.invalidate()
                requestedStorageLocation = location
            }
        )
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
                        .ghostFilledControlTint()
                    Toggle("Line Count", isOn: $settings.statusShowsLineCount)
                        .ghostFilledControlTint()
                    Toggle("Word Count", isOn: $settings.statusShowsWordCount)
                        .ghostFilledControlTint()
                    Toggle("Character Count", isOn: $settings.statusShowsCharacterCount)
                        .ghostFilledControlTint()
                    Toggle("Heading Level", isOn: $settings.statusShowsHeadingLevel)
                        .ghostFilledControlTint()
                    Toggle("Selected Word Count", isOn: $settings.statusShowsSelectedWordCount)
                        .ghostFilledControlTint()
                    Toggle(
                        "Selected Character Count",
                        isOn: $settings.statusShowsSelectedCharacterCount
                    )
                    .ghostFilledControlTint()
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
