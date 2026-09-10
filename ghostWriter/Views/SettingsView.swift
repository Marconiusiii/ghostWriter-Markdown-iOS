//
//  SettingsView.swift
//  ghostWriter
//
//  App-wide options. Everything here is a native Form control, so each row is
//  announced with its role, current value, and how to change it without any
//  accessibility work on our part.
//

import MessageUI
import StoreKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(DocumentStorage.self) private var storage
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var libraryMetadata
    @Environment(AppSettings.self) private var settings
    @Environment(SupportStore.self) private var supportStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingHelp = false
    @State private var showingWhyGhostWriter = false
    @State private var showingAcknowledgements = false
    @State private var showingStatusBarSettings = false
    @State private var showingMailComposer = false
    @State private var showingMailUnavailable = false
    @State private var requestedStorageLocation: DocumentStorageChoice?
    @State private var supportAlert: SupportAlertContent?
    @State private var showingSupportAlert = false
    @State private var supportConfirmation: SupportConfirmationContent?
    @State private var showingSupportConfirmation = false

    private struct SupportAlertContent {
        let title: String
        let message: String
    }

    private struct SupportConfirmationContent {
        let title: String
        let message: String
    }

    private struct SupportConfirmationSheet: View {
        @Environment(\.dismiss) private var dismiss

        let confirmation: SupportConfirmationContent

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(confirmation.title)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)

                    Text(confirmation.message)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
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
                    if storage.activeDirectory == nil { Text(storage.statusDescription) }
                } header: {
                    Text("Files")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("When App Opens")
                            .accessibilityHidden(true)
                        Picker(
                            "When App Opens",
                            selection: $settings.appLaunchBehavior
                        ) {
                            ForEach(AppLaunchBehavior.allCases) { behavior in
                                Text(behavior.label).tag(behavior)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                } header: {
                    Text("App Launch")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("When Starting a New Document")
                            .accessibilityHidden(true)
                        Picker(
                            "When Starting a New Document",
                            selection: $settings.newDocumentCreationMode
                        ) {
                            ForEach(NewDocumentCreationMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                } header: {
                    Text("New Documents")
                }

                Section {
                    Toggle("Use smart punctuation", isOn: $settings.usesSmartPunctuation)
                    Toggle("Use Word Stylesheet", isOn: $settings.usesWordStylesheet)
                    if settings.usesWordStylesheet { WordStylesheetStatusView() }
                } header: {
                    Text("Export")
                }

                Section("Editing") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Indentation")
                            .accessibilityHidden(true)
                        Picker("Indentation", selection: $settings.indentUnit) {
                            ForEach(IndentUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        .pickerStyle(.wheel)
                    }

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
                    Toggle("Heading Swipe Navigation", isOn: $settings.headingSwipeNavigationEnabled)
                        .ghostFilledControlTint()
                }

                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Theme")
                            .accessibilityHidden(true)
                        Picker("Theme", selection: $settings.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.wheel)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Editor Font")
                            .accessibilityHidden(true)
                        Picker("Editor Font", selection: $settings.editorFontDesign) {
                            ForEach(EditorFontDesign.allCases) { design in
                                Text(design.label).tag(design)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                }

                Section {
                    Toggle("Status Bar", isOn: $settings.statusBarEnabled)
                        .ghostFilledControlTint()
                        .accessibilityHint("Shows selected document information after the editor")

                    if settings.statusBarEnabled {
                        Button("Customize Status Bar") {
                            showingStatusBarSettings = true
                        }
                    }
                } header: {
                    Text("Editor Status")
                }

                Section {
                    Toggle("Render Sound", isOn: $settings.renderSoundEnabled)
                        .ghostFilledControlTint()
                        .accessibilityHint("Plays a tone when a document is rendered")
                } header: {
                    Text("Sound")
                }

                Section {
                    NavigationLink("Edit defaults") {
                        EBrailleMetadataSettingsView()
                    }
                } header: {
                    Text("eBraille metadata")
                }

                supportSection

                Section {
                    LabeledContent("Version", value: appVersion)
                    Button("Why ghostWriter?") {
                        showingWhyGhostWriter = true
                    }
                    .accessibilityHint("Opens the lore of ghostWriter")
                    Button("Acknowledgements") {
                        showingAcknowledgements = true
                    }
                    .accessibilityHint("Opens software acknowledgements and licenses")
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
                } header: {
                    Text("About")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(copyright)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Help") { showingHelp = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
            .task {
                if supportStore.products.count
                    != SupportStore.supportOptions.count {
                    await supportStore.loadProducts()
                }
            }
        }
        .sheet(isPresented: $showingSupportConfirmation) {
            if let supportConfirmation {
                SupportConfirmationSheet(
                    confirmation: supportConfirmation
                )
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(item: $requestedStorageLocation) { destination in
            ICloudMigrationView(
                destination: destination,
                onCompletion: {}
            )
            .environment(storage)
            .environment(store)
            .environment(libraryMetadata)
        }
        .sheet(isPresented: $showingWhyGhostWriter) {
            WhyGhostWriterView()
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingAcknowledgements) {
            AcknowledgementsView()
        }
        .sheet(isPresented: $showingStatusBarSettings) {
            StatusBarSettingsView()
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

    private var supportSection: some View {
        Section("Support ghostWriter Markdown") {
            if let statusText = supportStatusText {
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if supportStore.status == .productLoadFailed {
                Button("Try Again") {
                    Task { await supportStore.loadProducts() }
                }
            }

            ForEach(SupportStore.supportOptions) { option in
                Button {
                    Task {
                        await supportStore.purchase(option)
                        if case .success(let thankYou) = supportStore.status {
                            supportConfirmation = SupportConfirmationContent(
                                title: String(
                                    localized: "Friendly Haunting Received"
                                ),
                                message: thankYouText(thankYou)
                            )
                            showingSupportConfirmation = true
                        } else if let alert = supportAlertContent {
                            supportAlert = alert
                            showingSupportAlert = true
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(supportStore.displayName(for: option))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(supportPrice(for: option))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(
                    !supportStore.isAvailable(option)
                        || supportStore.isPurchasing
                )
            }
        }
        .alert(
            supportAlert?.title ?? "",
            isPresented: $showingSupportAlert,
            presenting: supportAlert
        ) { _ in
            Button("Done") { }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var supportAlertContent: SupportAlertContent? {
        let standardTitle = String(localized: "Support ghostWriter Markdown")

        switch supportStore.status {
        case .pending, .productLoadFailed, .purchaseFailed,
             .verificationFailed, .unexpected:
            guard let message = supportStatusText else { return nil }
            return SupportAlertContent(
                title: standardTitle,
                message: message
            )
        case .idle, .loading, .purchasing, .success:
            return nil
        }
    }

    private var supportStatusText: String? {
        switch supportStore.status {
        case .idle:
            return supportStore.latestThankYou.map(thankYouText)
        case .loading:
            return String(localized: "The support spirits are gathering…")
        case .purchasing(let name):
            return String.localizedStringWithFormat(
                String(localized: "Sending your %@ through the haunted halls…"),
                name
            )
        case .success(let thankYou):
            return thankYouText(thankYou)
        case .pending:
            return String(
                localized: "Your support is waiting for approval. The ghost will keep watch."
            )
        case .productLoadFailed:
            return String(
                localized: "The support options are hiding in the fog. Please check your connection and try again."
            )
        case .purchaseFailed:
            return String(
                localized: "That haunting lost its way. No support was recorded. Please try again."
            )
        case .verificationFailed:
            return String(
                localized: "The App Store could not verify this support, so nothing was recorded."
            )
        case .unexpected:
            return String(
                localized: "Something unexpected rattled the walls. No support was recorded."
            )
        }
    }

    private func supportPrice(for option: SupportStore.SupportOption) -> String {
        supportStore.displayPrice(for: option)
            ?? String(localized: "Price unavailable")
    }

    private func thankYouText(
        _ thankYou: SupportStore.SupportThankYou
    ) -> String {
        let date = thankYou.date.formatted(date: .long, time: .omitted)
        return String.localizedStringWithFormat(
            String(
                localized: "Thank you for your %@ on %@. ghostWriter is feeling pleasantly haunted."
            ),
            thankYou.supportName,
            date
        )
    }

    private var documentStorageBinding: Binding<DocumentStorageChoice> {
        Binding(
            get: { storage.selectedLocation },
            set: { location in
                guard location != storage.selectedLocation else { return }

                requestedStorageLocation = location
            }
        )
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: .now)
        return "© \(year) Marco Salsiccia"
    }

    private func sendFeedback() {
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
