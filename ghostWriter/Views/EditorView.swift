//
//  EditorView.swift
//  ghostWriter
//
//  The writing screen: a heading, the actions, then the editor.
//
//  The document is tracked by its file URL rather than by a Document value.
//  That matters: the store republishes its document list whenever it re-reads
//  the folder, and holding a value type across that could leave this screen
//  pointing at a stale record and writing a second file. A URL is stable.
//

import SwiftUI
import UIKit

struct EditorView: View {
    /// The file being edited. Nil until the first save creates it.
    @State private var fileURL: URL?
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
    /// The name the file was last saved under, so autosave does not rename on
    /// every keystroke as the first heading is typed.
    @State private var savedName: String?

    private let draftName: String

    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(document: Document, initialText: String) {
        _fileURL = State(initialValue: document.url)
        _text = State(initialValue: initialText)
        _savedName = State(initialValue: document.displayName)
        self.draftName = document.displayName
    }

    init(draftNamed name: String) {
        _fileURL = State(initialValue: nil)
        _text = State(initialValue: "")
        _savedName = State(initialValue: nil)
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
        .onAppear {
            // Warm the audio session now, so the cost of activating it is not
            // paid at the moment Render is tapped — that was the burst of
            // static at the start of the tone.
            if settings.renderSoundEnabled { RenderSound.shared.prepare() }
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
            MarkdownReferenceView()
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
                    present { showingOutline = true }
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
        } primaryAction: {
            // Put the keyboard away before the menu appears, so it does not
            // cover the menu it is opening.
            dismissKeyboard()
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
            pendingCursorOffset: $pendingCursorOffset,
            onIndent: { applyIndent(outdent: false) },
            onOutdent: { applyIndent(outdent: true) }
        )
    }

    // MARK: - Title

    /// The document's name, taken from its first heading, then its first
    /// non-empty line, then the name it was created with.
    private var displayTitle: String {
        if let savedName, derivedName.isEmpty { return savedName }
        if !derivedName.isEmpty { return derivedName }
        return savedName ?? draftName
    }

    /// The first meaningful line of the document, with markdown syntax removed.
    ///
    /// Every markdown marker is stripped, not just a well-formed heading. A
    /// half-typed "# " is still a heading in progress, and a bullet or quote
    /// marker is punctuation rather than a name — leaving any of it in produced
    /// filenames like "#".
    private var derivedName: String {
        for rawLine in text.components(separatedBy: "\n") {
            let stripped = EditorView.stripMarkdownSyntax(rawLine)
            if stripped.isEmpty { continue }
            return String(stripped.prefix(80))
        }
        return ""
    }

    /// Removes leading block markers and inline emphasis from a line so it can
    /// be used as a document name.
    static func stripMarkdownSyntax(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespaces)

        // Leading block markers: heading hashes, blockquote arrows, list
        // bullets, and numbered-list markers.
        while true {
            let before = line

            if line.hasPrefix("#") {
                line = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix(">") {
                line = String(line.drop { $0 == ">" }).trimmingCharacters(in: .whitespaces)
            }
            if let first = line.first, "-*+".contains(first),
               line.dropFirst().first == " " {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if let match = line.firstMatch(of: /^\d+[.)]\s+/) {
                line = String(line[match.range.upperBound...])
            }
            // A task box follows the bullet that was just removed.
            if line.hasPrefix("[ ] ") || line.lowercased().hasPrefix("[x] ") {
                line = String(line.dropFirst(4))
            }

            if line == before { break }
        }

        // Trailing hashes on a closed ATX heading.
        line = line.replacingOccurrences(of: "#+$", with: "", options: .regularExpression)

        // Inline emphasis and code markers, which are punctuation in a name.
        line = line.replacingOccurrences(of: "[*_`~]", with: "", options: .regularExpression)

        // Link syntax: keep the visible text, drop the target.
        line = line.replacingOccurrences(
            of: #"!?\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )

        return line.trimmingCharacters(in: .whitespaces)
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

    /// Dismisses the keyboard, then presents. Anything that puts content over
    /// the editor goes through this.
    private func present(_ action: @escaping () -> Void) {
        dismissKeyboard()
        action()
    }

    private func render() {
        dismissKeyboard()
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
        UIAccessibility.post(notification: .announcement, argument: result.announcement)
    }

    // MARK: - Saving

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNow(announce: false)
        }
    }

    /// Writes the document. Once a file exists it is always overwritten in
    /// place — the file is never recreated, and it is never renamed by
    /// autosave. Renaming happens only when the user asks for it.
    private func saveNow(announce shouldAnnounce: Bool) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard hasUnsavedChanges || shouldAnnounce else { return }

        if let url = fileURL {
            if store.save(text: text, to: url) {
                hasUnsavedChanges = false
                if shouldAnnounce { announce("Saved.") }
            } else if shouldAnnounce {
                announce("Could not save.")
            }
            return
        }

        // First save only: create the file.
        let name = derivedName.isEmpty ? draftName : derivedName
        guard let created = store.createDocument(named: name, contents: text) else {
            if shouldAnnounce { announce("Could not save.") }
            return
        }

        fileURL = created
        savedName = created.deletingPathExtension().lastPathComponent
        hasUnsavedChanges = false
        if shouldAnnounce { announce("Saved.") }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        saveNow(announce: false)
        guard let url = fileURL else {
            // Not on disk yet, so just remember the name for the first save.
            savedName = trimmed
            announce("Renamed to \(trimmed).")
            return
        }

        if let renamed = store.rename(at: url, to: trimmed) {
            fileURL = renamed
            savedName = renamed.deletingPathExtension().lastPathComponent
            announce("Renamed to \(savedName ?? trimmed).")
        } else {
            announce("Could not rename.")
        }
    }

    private func duplicate() {
        saveNow(announce: false)
        guard let url = fileURL,
              let document = Document(fileURL: url) else { return }
        if store.duplicate(document) != nil { announce("Duplicated.") }
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
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(4))
            if statusMessage == message { statusMessage = "" }
        }
    }
}
