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

nonisolated enum EditorSaveFeedback {
    static func explicitSaveMessage(
        usesICloudStorage: Bool
    ) -> String {
        usesICloudStorage
            ? "Saved. iCloud will upload changes in the background."
            : "Saved."
    }
}

struct EditorView: View {
    /// The file being edited. Nil until the first save creates it.
    @State private var fileURL: URL?
    @State private var text: String
    @State private var selection = TextSelection(location: 0, length: 0)
    @State private var statusIndex: DocumentStatusIndex?
    @State private var pendingCursorOffset: Int?
    @State private var pendingFindRequest: UUID?

    @State private var showingRendered = false
    @State private var showingOutline = false
    @State private var showingReference = false
    @State private var showingRename = false
    @State private var showingJumpToLine = false
    @State private var showingInsertActions = false
    @State private var insertionSelection = TextSelection(location: 0, length: 0)
    @State private var insertionInitialText = ""
    @State private var pendingInsertionResult: MarkdownInsertionResult?
    @State private var renameText = ""
    @State private var jumpLineText = ""
    @State private var jumpLineError: LineNavigationError?

    @State private var saveTask: Task<Void, Never>?
    @State private var hasUnsavedChanges = false
    @State private var lastSavedText: String
    @State private var suppressNextTextChange = false
    @State private var externalConflict: ExternalConflict?
    @State private var statusMessage = ""
    @State private var focusRequestGate = FocusRestorationRequestGate()
    @AccessibilityFocusState private var focusedElement: EditorFocus?
    /// The name the file was last saved under, so autosave does not rename on
    /// every keystroke as the first heading is typed.
    @State private var savedName: String?

    private let draftName: String
    private let onDocumentURLChange: (URL) -> Void
    private let onClose: (URL) -> Void

    private enum EditorFocus: Hashable {
        case render
        case insert
        case fileActions
    }

    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(DocumentLibraryMetadataStore.self) private var libraryMetadata
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        document: Document,
        initialText: String,
        onDocumentURLChange: @escaping (URL) -> Void = { _ in },
        onClose: @escaping (URL) -> Void = { _ in }
    ) {
        _fileURL = State(initialValue: document.url)
        _text = State(initialValue: initialText)
        _statusIndex = State(initialValue: nil)
        _pendingCursorOffset = State(
            initialValue: EditorPositionStore.shared.position(for: document.url)
        )
        _lastSavedText = State(initialValue: initialText)
        _savedName = State(initialValue: document.displayName)
        self.draftName = document.displayName
        self.onDocumentURLChange = onDocumentURLChange
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            editor
            if settings.statusBarEnabled {
                statusBar
            }
        }
        .background(Color.editorBackground)
        .navigationBarHidden(true)
        .onChange(of: text) { _, _ in
            if settings.statusBarEnabled {
                statusIndex = DocumentStatusIndex(text: text)
            }
            if suppressNextTextChange {
                suppressNextTextChange = false
                return
            }
            hasUnsavedChanges = true
            scheduleAutosave()
        }
        .onAppear {
            if settings.statusBarEnabled {
                statusIndex = DocumentStatusIndex(text: text)
            }
            // Warm the audio session now, so the cost of activating it is not
            // paid at the moment Render is tapped — that was the burst of
            // static at the start of the tone.
            if settings.renderSoundEnabled { RenderSound.shared.prepare() }
        }
        .onChange(of: settings.statusBarEnabled) { _, isEnabled in
            statusIndex = isEnabled ? DocumentStatusIndex(text: text) : nil
        }
        .onChange(of: focusedElement) { _, element in
            // VoiceOver activation does not pass through the touch gesture
            // attached to the Menu. Put the keyboard away when VoiceOver
            // reaches File Actions so it is already gone before the native
            // menu opens.
            if element == .fileActions {
                dismissKeyboard()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkForExternalChanges()
            } else {
                persistEditingPosition()
                saveNow(announce: false)
            }
        }
        .onDisappear {
            saveTask?.cancel()
            persistEditingPosition()
            saveNow(announce: false)
            RenderSound.shared.stop()
        }
        .fullScreenCover(isPresented: $showingRendered, onDismiss: {
            restoreFocus(to: .render)
        }) {
            RenderedHTMLView(title: displayTitle, markdown: text)
        }
        .sheet(isPresented: $showingOutline) {
            OutlineView(entries: OutlineBuilder.build(from: text)) { offset in
                pendingCursorOffset = offset
            }
        }
        .sheet(isPresented: $showingReference, onDismiss: {
            restoreFocus(to: .fileActions)
        }) {
            MarkdownReferenceView()
        }
        .sheet(isPresented: $showingInsertActions, onDismiss: finishInsertionPresentation) {
            InsertActionsView(initialLinkText: insertionInitialText) { command in
                pendingInsertionResult = MarkdownInsertion.apply(
                    command,
                    in: text,
                    selection: insertionSelection
                )
            }
            .presentationDragIndicator(.hidden)
        }
        .alert("Rename Document", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                restoreFocus(to: .fileActions)
            }
            Button("Rename") {
                commitRename()
                if store.lastError == nil {
                    restoreFocus(to: .fileActions)
                }
            }
        } message: {
            Text("Enter a new name for this document.")
        }
        .alert("Jump to Line", isPresented: $showingJumpToLine) {
            TextField("Line number", text: $jumpLineText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                restoreFocus(to: .fileActions)
            }
            Button("Jump") {
                jumpToLine()
            }
        } message: {
            Text(
                "Enter a line number from 1 through \(LineNavigation.lineCount(in: text))."
            )
        }
        .alert(
            jumpLineError?.title ?? "Could Not Jump",
            isPresented: jumpLineErrorBinding,
            presenting: jumpLineError
        ) { _ in
            Button("Try Again") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingJumpToLine = true
                }
            }
            Button("Cancel", role: .cancel) {
                restoreFocus(to: .fileActions)
            }
        } message: { error in
            Text(error.message)
        }
        .alert("ghostWriter Error", isPresented: errorBinding) {
            Button("OK") {
                store.lastError = nil
                restoreFocus(to: .fileActions)
            }
        } message: {
            Text(store.lastError ?? "An unknown error occurred.")
        }
        .alert(
            externalConflict?.title ?? "Document Changed",
            isPresented: externalConflictBinding,
            presenting: externalConflict
        ) { conflict in
            switch conflict {
            case .changed(let externalText):
                Button("Save Mine as a Copy") {
                    saveCurrentTextAsNewDocument(
                        preferredName: "\(displayTitle) copy"
                    )
                }
                Button("Reload External Version", role: .destructive) {
                    reloadExternalVersion(externalText)
                }
                Button("Cancel", role: .cancel) { }
            case .missing:
                Button("Save as New Document") {
                    saveCurrentTextAsNewDocument(
                        preferredName: displayTitle
                    )
                }
                Button("Close Without Saving", role: .destructive) {
                    closeWithoutSaving()
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: { conflict in
            Text(conflict.message)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                closeEditor()
            } label: {
                Label("Documents", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Back")
            .keyboardShortcut(shortcut("w", modifiers: .command))

            Text(displayTitle)
                .font(.title2.bold())
                .foregroundStyle(Color.ghostAccent)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            editorActions

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

    @ViewBuilder
    private var editorActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                renderButton
                outlineButton
                insertButton
                fileActionsMenu
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    renderButton
                    outlineButton
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    insertButton
                    fileActionsMenu
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var renderButton: some View {
        Button {
            render()
        } label: {
            Label("Render", systemImage: "doc.richtext")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Shows this document as formatted HTML")
        .accessibilityFocused($focusedElement, equals: .render)
        .keyboardShortcut(shortcut("r", modifiers: .command))
    }

    private var outlineButton: some View {
        Button {
            present { showingOutline = true }
        } label: {
            Label("Outline", systemImage: "list.bullet.indent")
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Shows a list of document headings")
        .keyboardShortcut(
            shortcut("o", modifiers: [.command, .shift])
        )
    }

    private var insertButton: some View {
        Button {
            beginInsertion()
        } label: {
            Label("Insert…", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Opens list of insertable Markdown elements")
        .accessibilityFocused($focusedElement, equals: .insert)
        .keyboardShortcut(
            shortcut("i", modifiers: [.command, .shift])
        )
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

            Button {
                focusRequestGate.invalidate()
                pendingFindRequest = UUID()
            } label: {
                Label("Find and Replace", systemImage: "magnifyingglass")
            }
            .keyboardShortcut(shortcut("f", modifiers: .command))

            Button {
                jumpLineText = ""
                present { showingJumpToLine = true }
            } label: {
                Label("Jump to Line…", systemImage: "arrow.down.to.line")
            }
            .keyboardShortcut(shortcut("j", modifiers: .command))

            Divider()

            Button {
                saveNow(announce: true)
            } label: {
                Label("Save Now", systemImage: "arrow.down.doc")
            }
            .keyboardShortcut(shortcut("s", modifiers: .command))

            Menu {
                ShareLink(
                    item: markdownShareFile,
                    preview: SharePreview("\(displayTitle), Markdown")
                ) {
                    Text("Markdown")
                }

                ShareLink(
                    item: plainTextShareFile,
                    preview: SharePreview("\(displayTitle), Plain Text")
                ) {
                    Text("Plain Text")
                }

                ShareLink(
                    item: htmlShareFile,
                    preview: SharePreview("\(displayTitle), HTML")
                ) {
                    Text("HTML")
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
        .accessibilityFocused($focusedElement, equals: .fileActions)
        .simultaneousGesture(
            TapGesture().onEnded {
                // Preserve Menu's native activation while dismissing the
                // editor keyboard for direct-touch users.
                dismissKeyboard()
            }
        )
    }

    // MARK: - Editor

    private var editor: some View {
        MarkdownTextView(
            text: $text,
            selection: $selection,
            smartListsEnabled: settings.smartListsEnabled,
            editorFontDesign: settings.editorFontDesign,
            keyboardShortcutsEnabled: settings.keyboardShortcutsEnabled,
            pendingCursorOffset: $pendingCursorOffset,
            pendingFindRequest: $pendingFindRequest,
            onIndent: { applyIndent(outdent: false) },
            onOutdent: { applyIndent(outdent: true) }
        )
    }

    /// A single, quiet focus stop after the editor. Updating this text never
    /// posts an announcement, so it cannot compete with typing feedback. A
    /// writer hears it only by navigating out of the editor and into the bar.
    private var statusBar: some View {
        Text(statusBarText)
            .font(.footnote)
            .foregroundStyle(Color.ghostMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.panelBackground)
            .accessibilityIdentifier("editor-status-bar")
    }

    private var statusBarText: String {
        (statusIndex ?? DocumentStatusIndex(text: text))
            .status(selection: selection)
            .description(options: statusBarOptions)
    }

    private var statusBarOptions: DocumentStatusOptions {
        DocumentStatusOptions(
            lineAndColumn: settings.statusShowsLineAndColumn,
            lineCount: settings.statusShowsLineCount,
            wordCount: settings.statusShowsWordCount,
            characterCount: settings.statusShowsCharacterCount,
            headingLevel: settings.statusShowsHeadingLevel,
            selectedWordCount: settings.statusShowsSelectedWordCount,
            selectedCharacterCount: settings.statusShowsSelectedCharacterCount
        )
    }

    // MARK: - Title

    /// The document's name. Chosen by the user when the document was created,
    /// and changed only by an explicit rename — never inferred from the text.
    private var displayTitle: String {
        savedName ?? draftName
    }

    private var shareFileName: String {
        DocumentStore.sanitize(displayTitle)
    }

    private var markdownShareFile: MarkdownShareFile {
        MarkdownShareFile(fileName: shareFileName, contents: text)
    }

    private var plainTextShareFile: PlainTextShareFile {
        PlainTextShareFile(fileName: shareFileName, contents: text)
    }

    private var htmlShareFile: HTMLShareFile {
        HTMLShareFile(
            fileName: shareFileName,
            contents: ShareItemBuilder.contents(
                title: displayTitle,
                markdown: text,
                format: .html
            )
        )
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
        focusRequestGate.invalidate()
        dismissKeyboard()
        action()
    }

    private func render() {
        focusRequestGate.invalidate()
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

    private func beginInsertion() {
        insertionSelection = selection
        insertionInitialText = MarkdownInsertion.selectedText(
            in: text,
            selection: selection
        )
        pendingInsertionResult = nil
        present { showingInsertActions = true }
    }

    private func finishInsertionPresentation() {
        guard let result = pendingInsertionResult else {
            restoreFocus(to: .insert)
            return
        }

        pendingInsertionResult = nil
        applyInsertion(result)
    }

    private func applyInsertion(_ result: MarkdownInsertionResult) {
        focusRequestGate.invalidate()
        dismissKeyboard()
        text = result.text
        selection = result.selection
        pendingCursorOffset = result.selection.location
    }

    private func jumpToLine() {
        switch LineNavigation.destination(for: jumpLineText, in: text) {
        case .success(let offset):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pendingCursorOffset = offset
            }
        case .failure(let error):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                jumpLineError = error
            }
        }
    }

    // MARK: - Saving

    private func persistEditingPosition() {
        guard let url = fileURL else { return }
        EditorPositionStore.shared.save(
            position: min(max(0, selection.location), text.count),
            for: url
        )
    }

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

        switch store.save(
            text: text,
            to: url,
            ifUnchangedFrom: lastSavedText
        ) {
        case .saved:
            lastSavedText = text
            hasUnsavedChanges = false
            if shouldAnnounce {
                announce(
                    EditorSaveFeedback.explicitSaveMessage(
                        usesICloudStorage: store.usesICloudStorage
                    )
                )
            }
        case .changedOnDisk(let externalText):
            showExternalConflict(.changed(externalText))
        case .missing:
            showExternalConflict(.missing)
        case .failed:
            if shouldAnnounce { announce("Could not save.") }
        }
    }

    /// Checks as soon as the app returns from Files, rather than waiting for
    /// the next keystroke and autosave attempt to reveal the conflict.
    private func checkForExternalChanges() {
        guard externalConflict == nil, let url = fileURL else { return }

        switch store.diskState(for: url, expectedContents: lastSavedText) {
        case .unchanged:
            break
        case .changed(let externalText):
            showExternalConflict(.changed(externalText))
        case .missing:
            showExternalConflict(.missing)
        case .unreadable:
            break
        }
    }

    private func showExternalConflict(_ conflict: ExternalConflict) {
        saveTask?.cancel()
        dismissKeyboard()
        externalConflict = conflict
    }

    private func reloadExternalVersion(_ externalText: String) {
        dismissKeyboard()
        suppressNextTextChange = true
        text = externalText
        lastSavedText = externalText
        hasUnsavedChanges = false
        externalConflict = nil
        announce("Reloaded the version from Files.")
    }

    private func saveCurrentTextAsNewDocument(preferredName: String) {
        let previousURL = fileURL
        let contents = text
        let replacesMissingDocument: Bool
        if case .missing = externalConflict {
            replacesMissingDocument = true
        } else {
            replacesMissingDocument = false
        }

        Task {
            guard let newURL = await store.createDocument(
                named: preferredName,
                contents: contents,
                in: previousURL.map(store.containingDirectory(for:))
            ) else { return }

            if let previousURL {
                EditorPositionStore.shared.migratePosition(
                    from: previousURL,
                    to: newURL
                )
                if replacesMissingDocument {
                    libraryMetadata.migrateMetadata(
                        from: previousURL,
                        to: newURL
                    )
                } else {
                    libraryMetadata.recordOpened(newURL)
                }
            }
            fileURL = newURL
            onDocumentURLChange(newURL)
            savedName = newURL.deletingPathExtension().lastPathComponent
            lastSavedText = contents
            hasUnsavedChanges = false
            externalConflict = nil
            announce("Saved as \(savedName ?? preferredName).")
        }
    }

    /// The custom Back button must not leave while an attempted guarded save
    /// still has local work outstanding. That would make Cancel on a conflict
    /// alert meaningless and discard the in-memory version when the view closes.
    private func closeEditor() {
        saveNow(announce: false)
        guard !hasUnsavedChanges else { return }
        if let fileURL {
            onClose(fileURL)
        }
        dismiss()
    }

    private func closeWithoutSaving() {
        saveTask?.cancel()
        hasUnsavedChanges = false
        externalConflict = nil
        if let fileURL {
            onClose(fileURL)
        }
        dismiss()
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        saveNow(announce: false)
        guard !hasUnsavedChanges else { return }
        guard let url = fileURL else { return }

        if let renamed = store.rename(at: url, to: trimmed) {
            EditorPositionStore.shared.migratePosition(from: url, to: renamed)
            libraryMetadata.migrateMetadata(from: url, to: renamed)
            fileURL = renamed
            onDocumentURLChange(renamed)
            savedName = renamed.deletingPathExtension().lastPathComponent
            announce("Renamed to \(savedName ?? trimmed).")
        } else {
            announce("Could not rename.")
        }
    }

    private func duplicate() {
        saveNow(announce: false)
        guard !hasUnsavedChanges else { return }
        guard let url = fileURL,
              let document = Document(fileURL: url) else { return }
        Task {
            if await store.duplicate(document) != nil {
                announce("Duplicated.")
            }
        }
    }

    private func announce(_ message: String) {
        statusMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(4))
            if statusMessage == message { statusMessage = "" }
        }
    }

    private func shortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> KeyboardShortcut? {
        settings.keyboardShortcutsEnabled
            ? KeyboardShortcut(key, modifiers: modifiers)
            : nil
    }

    private func restoreFocus(to target: EditorFocus) {
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }

    private var jumpLineErrorBinding: Binding<Bool> {
        Binding(
            get: { jumpLineError != nil },
            set: { if !$0 { jumpLineError = nil } }
        )
    }

    private var externalConflictBinding: Binding<Bool> {
        Binding(
            get: { externalConflict != nil },
            set: { if !$0 { externalConflict = nil } }
        )
    }
}

private enum ExternalConflict {
    case changed(String)
    case missing

    var title: String {
        switch self {
        case .changed:
            return "Document Changed in Files"
        case .missing:
            return "Document Removed in Files"
        }
    }

    var message: String {
        switch self {
        case .changed:
            return "This document changed outside ghostWriter. Save your current work as a copy or reload the external version."
        case .missing:
            return "This document was removed outside ghostWriter. Save your current work as a new document or close without saving."
        }
    }
}
