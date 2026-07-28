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
            // Each item puts the keyboard away before presenting, so nothing
            // appears underneath it.
            Button {
                renameText = displayTitle
                present { showingRename = true }
            } label: {
                Label("Rename Document", systemImage: "pencil")
            }

            Button {
                present { showingReference = true }
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
                    Button(format.label) { present { share(as: format) } }
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
            pendingCursorOffset: $pendingCursorOffset,
            onIndent: { applyIndent(outdent: false) },
            onOutdent: { applyIndent(outdent: true) }
        )
    }

    // MARK: - Title

    /// The document's name. Chosen by the user when the document was created,
    /// and changed only by an explicit rename — never inferred from the text.
    private var displayTitle: String {
        savedName ?? draftName
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

    /// Writes the document. The file always exists by the time the editor is on
    /// screen — it is created with the name the user gave — so this only ever
    /// overwrites in place. It never creates and never renames.
    private func saveNow(announce shouldAnnounce: Bool) {
        guard hasUnsavedChanges || shouldAnnounce else { return }
        guard let url = fileURL else { return }

        if store.save(text: text, to: url) {
            hasUnsavedChanges = false
            if shouldAnnounce { announce("Saved.") }
        } else if shouldAnnounce {
            announce("Could not save.")
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        saveNow(announce: false)
        guard let url = fileURL else { return }

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
