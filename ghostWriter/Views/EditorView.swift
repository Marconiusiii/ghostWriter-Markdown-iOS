//
//  EditorView.swift
//  ghostWriter
//
//  The writing screen: a heading, the actions, then the editor. Nothing else.
//  No search field, no rendered preview beside it, no title text field
//  competing with the text view for focus.
//
//  The document's name comes from its first heading, or failing that its first
//  line of text, so a writer never has to name a file before writing in it.
//  Renaming is an explicit action in the File Actions menu.
//

import SwiftUI
import UIKit

struct EditorView: View {
    /// Nil until the document has been written to disk for the first time.
    @State private var document: Document?
    @State private var text: String
    @State private var selection = TextSelection(location: 0, length: 0)
    @State private var pendingCursorOffset: Int?

    @State private var showingRendered = false
    @State private var showingOutline = false
    @State private var showingReference = false
    @State private var showingShare = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var shareItems: [Any] = []

    @State private var saveTask: Task<Void, Never>?
    @State private var hasUnsavedChanges = false
    @State private var statusMessage = ""

    /// The name used until the file exists on disk.
    private let draftName: String

    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    /// Opens an existing document.
    init(document: Document, initialText: String) {
        _document = State(initialValue: document)
        _text = State(initialValue: initialText)
        self.draftName = document.displayName
    }

    /// Opens a blank draft that is not on disk yet.
    init(draftNamed name: String) {
        _document = State(initialValue: nil)
        _text = State(initialValue: "")
        self.draftName = name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            editor
        }
        .background(Color.editorBackground)
        .navigationBarHidden(true)
        .onChange(of: text) { _, _ in
            hasUnsavedChanges = true
            scheduleAutosave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNow(announce: false) }
        }
        .onDisappear {
            saveTask?.cancel()
            saveNow(announce: false)
            RenderSound.shared.stop()
        }
        .fullScreenCover(isPresented: $showingRendered) {
            RenderedHTMLView(title: displayTitle, markdown: text)
        }
        .sheet(isPresented: $showingOutline) {
            OutlineView(entries: OutlineBuilder.build(from: text)) { offset in
                pendingCursorOffset = offset
            }
        }
        .sheet(isPresented: $showingReference) {
            MarkdownReferenceView { snippet in insert(snippet) }
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: shareItems)
        }
        .alert("Rename Document", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { }
            Button("Rename") { commitRename() }
        } message: {
            Text("Enter a new name for this document.")
        }
    }

    // MARK: - Header

    /// Back, then the document name as a heading, then the actions. Read in
    /// that order because they are written in that order.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                saveNow(announce: false)
                dismiss()
            } label: {
                Label("Documents", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Back to documents")

            Text(displayTitle)
                .font(.title2.bold())
                .foregroundStyle(Color.ghostAccent)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    render()
                } label: {
                    Label("Render", systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Shows this document as formatted HTML")

                Button {
                    showingOutline = true
                } label: {
                    Label("Outline", systemImage: "list.bullet.indent")
                }
                .buttonStyle(.bordered)

                fileActionsMenu

                Spacer(minLength: 0)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.ghostMuted)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.panelBackground)
    }

    private var fileActionsMenu: some View {
        Menu {
            Button {
                renameText = displayTitle
                showingRename = true
            } label: {
                Label("Rename Document", systemImage: "pencil")
            }

            Button {
                showingReference = true
            } label: {
                Label("Markdown Reference", systemImage: "questionmark.circle")
            }

            Divider()

            Button {
                saveNow(announce: true)
            } label: {
                Label("Save Now", systemImage: "arrow.down.doc")
            }

            Menu {
                ForEach(ShareItemBuilder.Format.allCases) { format in
                    Button(format.label) { share(as: format) }
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                duplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
        } label: {
            Label("File Actions", systemImage: "ellipsis.circle")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("File actions")
    }

    // MARK: - Editor

    private var editor: some View {
        MarkdownTextView(
            text: $text,
            selection: $selection,
            smartListsEnabled: settings.smartListsEnabled,
            pendingCursorOffset: $pendingCursorOffset
        )
        .toolbar { keyboardToolbar }
    }

    /// Indent, outdent, and an explicit Dismiss so the keyboard can always be
    /// put away.
    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button {
                applyIndent(outdent: true)
            } label: {
                Label("Outdent", systemImage: "decrease.indent")
            }
            .accessibilityLabel("Outdent")

            Button {
                applyIndent(outdent: false)
            } label: {
                Label("Indent", systemImage: "increase.indent")
            }
            .accessibilityLabel("Indent")

            Spacer()

            Button {
                dismissKeyboard()
            } label: {
                Label("Dismiss Keyboard", systemImage: "keyboard.chevron.compact.down")
            }
            .accessibilityLabel("Dismiss keyboard")
        }
    }

    // MARK: - Title

    /// The document's name, taken from its first heading, then its first
    /// non-empty line, then the name it was created with. This is why there is
    /// no title field to fill in before writing.
    private var displayTitle: String {
        if !derivedName.isEmpty { return derivedName }
        return document?.displayName ?? draftName
    }

    private var derivedName: String {
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let level = LineAnalyzer.headingLevel(line) {
                let title = String(line.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return String(title.prefix(80)) }
            }

            // Not a heading, so use the first line of prose instead.
            return String(line.prefix(80))
        }
        return ""
    }

    // MARK: - Actions

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func render() {
        if settings.renderSoundEnabled { RenderSound.shared.play() }
        saveNow(announce: false)
        showingRendered = true
    }

    private func applyIndent(outdent: Bool) {
        let result = outdent
            ? Indentation.outdent(text: text, selection: selection, unit: settings.indentUnit)
            : Indentation.indent(text: text, selection: selection, unit: settings.indentUnit)

        text = result.text
        pendingCursorOffset = result.selection.location
        announce(result.announcement)
    }

    private func insert(_ snippet: String) {
        let characters = Array(text)
        let cursor = min(max(selection.location, 0), characters.count)

        let before = String(characters[0..<cursor])
        let after = String(characters[cursor...])
        let needsLeading = !before.isEmpty && !before.hasSuffix("\n")
        let needsTrailing = !after.isEmpty && !after.hasPrefix("\n")

        let insertion = (needsLeading ? "\n" : "") + snippet + (needsTrailing ? "\n" : "")
        text = before + insertion + after
        pendingCursorOffset = cursor + insertion.count
        announce("Example inserted.")
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNow(announce: false)
        }
    }

    private func saveNow(announce shouldAnnounce: Bool) {
        // A draft is only written once there is something in it, so tapping
        // New Document and backing out leaves no empty file behind.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard hasUnsavedChanges || shouldAnnounce else { return }

        if let existing = document {
            if store.save(text: text, to: existing) != nil {
                hasUnsavedChanges = false
                if shouldAnnounce { announce("Saved.") }
            } else if shouldAnnounce {
                announce("Could not save.")
            }
        } else {
            // First save: create the file using the derived name.
            let name = derivedName.isEmpty ? draftName : derivedName
            guard let created = store.createDocument(named: name) else {
                if shouldAnnounce { announce("Could not save.") }
                return
            }
            document = store.save(text: text, to: created) ?? created
            hasUnsavedChanges = false
            if shouldAnnounce { announce("Saved.") }
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        saveNow(announce: false)
        guard let existing = document else { return }

        if let renamed = store.rename(existing, to: trimmed) {
            document = renamed
            announce("Renamed to \(renamed.displayName).")
        } else {
            announce("Could not rename.")
        }
    }

    private func duplicate() {
        saveNow(announce: false)
        guard let existing = document else { return }
        if store.duplicate(existing) != nil { announce("Duplicated.") }
    }

    private func share(as format: ShareItemBuilder.Format) {
        saveNow(announce: false)
        guard let url = ShareItemBuilder.makeFile(
            title: displayTitle,
            markdown: text,
            format: format
        ) else {
            announce("Could not prepare the file.")
            return
        }
        shareItems = [url]
        showingShare = true
    }

    private func announce(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            if statusMessage == message { statusMessage = "" }
        }
    }
}
