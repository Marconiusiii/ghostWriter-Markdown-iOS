//
//  LibraryView.swift
//  ghostWriter
//
//  The home screen.
//
//  Everything here is laid out top to bottom in the order it should be read:
//  the app heading first, then Settings, then the sort and search controls
//  together, then the document list. There is no navigation title and no
//  `.searchable` modifier, because both place chrome outside the view's own
//  order — the navigation bar is read before the content regardless of where it
//  appears in code, and `.searchable` puts the field wherever the system likes.
//  Building these as ordinary views is what makes reading order match code
//  order without a single accessibility ordering trick.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var renderingSession: RenderedDocumentSession?
    @State private var renamingDocument: Document?
    @State private var pendingDeletion: Document?
    @State private var newName = ""
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var openedDocument: DocumentSession?
    @State private var showingNewDocument = false
    @State private var showingImporter = false
    @State private var shouldRestoreNewDocumentFocus = false
    @State private var focusAfterEditor: LibraryFocus?
    @State private var focusAfterPresentation: LibraryFocus?
    @State private var focusAfterError: LibraryFocus?
    @State private var searchAnnounceTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var focusedElement: LibraryFocus?

    private enum LibraryFocus: Hashable {
        case settings
        case newDocument
        case importDocument
        case sort
        case search
        case documentsHeading
        case document(URL)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                documentArea
                // Holds the content at the top of the screen. Without this the
                // stack sizes to its contents and centres itself vertically
                // once the list is short or empty.
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.pageBackground)
            // The heading below is the screen's title, so the bar is hidden
            // rather than duplicating it above the content.
            .navigationBarHidden(true)
            .navigationDestination(item: $openedDocument) { session in
                EditorView(
                    document: session.document,
                    initialText: session.text,
                    onDocumentURLChange: { url in
                        focusAfterEditor = .document(url)
                    }
                )
            }
            // Saving no longer republishes the store's list — that churn was
            // what let the editor lose track of its file — so the library
            // re-reads the folder when it comes back into view.
            .onChange(of: openedDocument) { _, value in
                if value == nil {
                    store.refresh()
                    if let target = focusAfterEditor {
                        restoreFocus(to: availableFocus(target))
                        focusAfterEditor = nil
                    }
                }
            }
            .onChange(of: searchText) { _, _ in
                scheduleSearchAnnouncement()
            }
        }
        .onAppear { store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            restoreFocus(to: .settings)
        }) {
            SettingsView()
        }
        .sheet(isPresented: $showingNewDocument, onDismiss: {
            if shouldRestoreNewDocumentFocus {
                restoreFocus(to: .newDocument)
            }
            shouldRestoreNewDocumentFocus = false
        }) {
            NewDocumentView { name in
                createDocument(named: name)
            }
        }
        .fullScreenCover(item: $renderingSession, onDismiss: {
            restorePresentationFocus()
        }) { session in
            RenderedHTMLView(
                title: session.title,
                markdown: session.markdown
            )
        }
        .sheet(isPresented: $showingShare, onDismiss: {
            restorePresentationFocus()
        }) {
            ShareSheet(items: shareItems)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("Rename Document", isPresented: renameBinding) {
            TextField("Name", text: $newName)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { cancelRename() }
            Button("Rename") { commitRename() }
        } message: {
            Text("Enter a new name for this document.")
        }
        .alert("Delete Document?", isPresented: deleteBinding) {
            Button("Cancel", role: .cancel) { cancelDelete() }
            Button("Delete", role: .destructive) {
                commitDelete()
            }
        } message: {
            Text(pendingDeletion.map { "\($0.displayName) will be deleted. This cannot be undone." } ?? "")
        }
        .alert("ghostWriter Error", isPresented: errorBinding) {
            Button("OK") { dismissError() }
        } message: {
            Text(store.lastError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Header

    /// The screen's reading order, written in the order it should be heard:
    /// app heading, Settings, New Document, then the Documents heading with the
    /// controls that act on that list directly beneath it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ghostWriter Markdown")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.ghostAccent)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .accessibilityFocused($focusedElement, equals: .settings)

            // New Document is the primary action, so it comes straight after
            // Settings rather than being buried among the list filters.
            Button {
                newDocument()
            } label: {
                Label("New Document", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityFocused($focusedElement, equals: .newDocument)

            Button {
                showingImporter = true
            } label: {
                Label("Import Document", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Copies markdown or plain-text files into ghostWriter")
            .accessibilityFocused($focusedElement, equals: .importDocument)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Two clearly separated groups under their own headings, rather than two
    /// pickers whose options run together as one undifferentiated list.
    private var sortMenu: some View {
        return Menu {
            Section("Sort By") {
                Picker("Sort By", selection: sortFieldBinding) {
                    ForEach(DocumentSortField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Sort Order") {
                Picker("Sort Order", selection: sortDirectionBinding) {
                    ForEach(SortDirection.allCases) { direction in
                        Text(direction.label(for: settings.sort.field)).tag(direction)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Sort")
        .accessibilityValue(settings.sort.spokenDescription)
        .accessibilityFocused($focusedElement, equals: .sort)
    }

    /// An ordinary text field rather than `.searchable`, so it stays where it is
    /// written. VoiceOver reaches exactly one element here: the field itself,
    /// labelled "Search". The visible label beside it is decoration.
    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Visible for sighted users only. It is hidden from VoiceOver
                // because the field below already carries "Search" as its
                // label — leaving it visible to assistive technology makes it
                // a separate stop that says the same word twice.
                Text("Search")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ghostText)
                    .accessibilityHidden(true)

                TextField("", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.ghostBorder, lineWidth: 1)
                    )
                    .accessibilityLabel("Search")
                    .accessibilityFocused($focusedElement, equals: .search)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Dismiss") {
                                searchFocused = false
                            }
                            .accessibilityLabel("Dismiss keyboard")
                        }
                    }
            }

            // Only present while there is something to clear.
            if !trimmedSearch.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Clears the search and shows all documents")
            }
        }
    }

    /// Clears the query, restores the full list, and puts focus back on the
    /// field — the Clear button itself is about to disappear, so leaving focus
    /// on it would strand VoiceOver on nothing.
    private func clearSearch() {
        searchText = ""
        searchFocused = true
        restoreFocus(to: .search)
        announceCount(prefix: "Showing")
    }

    /// Waits for typing to settle, then says how many documents match. Firing
    /// on every keystroke would talk over the letters being typed.
    private func scheduleSearchAnnouncement() {
        searchAnnounceTask?.cancel()
        searchAnnounceTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            announceCount(prefix: "Showing")
        }
    }

    private func announceCount(prefix: String) {
        let count = visibleDocuments.count
        let noun = count == 1 ? "document" : "documents"
        UIAccessibility.post(notification: .announcement, argument: "\(prefix) \(count) \(noun)")
    }

    // MARK: - List

    /// "Documents" is the heading. The count is ordinary text beneath the
    /// search field, where it doubles as the search result announcement.
    private var documentArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documents")
                .font(.title2.bold())
                .foregroundStyle(Color.ghostAccent)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedElement, equals: .documentsHeading)

            sortMenu
            searchField

            Text(countDescription)
                .font(.subheadline)
                .foregroundStyle(Color.ghostMuted)
                .accessibilityAddTraits(.updatesFrequently)

            list
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var list: some View {
        if store.documents.isEmpty {
            emptyLibrary
        } else if visibleDocuments.isEmpty {
            noSearchResults
        } else {
            documentList
        }
    }

    private var documentList: some View {
        // No section header here: the count heading above this list is the
        // heading for it, and repeating it would be a second announcement of
        // the same thing.
        List {
            ForEach(visibleDocuments) { document in
                    Button {
                        open(document)
                    } label: {
                        DocumentRow(
                            document: document,
                            onRender: { render(document) },
                            onShare: { share(document) },
                            onRename: { beginRename(document) },
                            onDuplicate: { duplicate(document) },
                            onDelete: { pendingDeletion = document }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityFocused(
                        $focusedElement,
                        equals: .document(document.url)
                    )
                    // Swipe actions serve touch users. VoiceOver users get the
                    // same capabilities through the row's custom actions, so
                    // these are hidden from assistive technology rather than
                    // being announced a second time.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletion = document
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityHidden(true)

                        Button {
                            beginRename(document)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .accessibilityHidden(true)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            render(document)
                        } label: {
                            Label("Render", systemImage: "doc.richtext")
                        }
                        .accessibilityHidden(true)

                        Button {
                            share(document)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityHidden(true)
                    }
                    // The surrounding stack supplies the horizontal padding, so
                    // the list rows do not add their own on top of it.
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // Neither empty state carries a heading. The Documents heading and the
    // count text above already say there is nothing here, so a third element
    // repeating it is just another stop on the way to the New Document button.
    // What remains is the one thing the count does not convey: what to do next.

    private var emptyLibrary: some View {
        Text("Tap New Document to start writing in markdown.")
            .font(.body)
            .foregroundStyle(Color.ghostMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var noSearchResults: some View {
        Text("No documents match \(trimmedSearch).")
            .font(.body)
            .foregroundStyle(Color.ghostMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Data

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleDocuments: [Document] {
        let query = trimmedSearch
        let filtered: [Document]

        if query.isEmpty {
            filtered = store.documents
        } else {
            filtered = store.documents.filter { document in
                if document.displayName.localizedCaseInsensitiveContains(query) { return true }
                return (try? store.text(for: document, reportFailure: false))?
                    .localizedCaseInsensitiveContains(query) == true
            }
        }

        return settings.sort.sorted(filtered)
    }

    private var countDescription: String {
        let count = visibleDocuments.count
        let noun = count == 1 ? "document" : "documents"
        return trimmedSearch.isEmpty ? "\(count) \(noun)" : "Showing \(count) \(noun)"
    }

    // MARK: - Actions

    private func open(_ document: Document) {
        focusAfterError = .document(document.url)
        guard let text = try? store.text(for: document) else { return }
        focusAfterError = nil
        focusAfterEditor = .document(document.url)
        openedDocument = DocumentSession(document: document, text: text)
    }

    private func render(_ document: Document) {
        focusAfterError = .document(document.url)
        guard let text = try? store.text(for: document) else { return }
        focusAfterError = nil
        focusAfterPresentation = .document(document.url)
        renderingSession = RenderedDocumentSession(
            title: document.displayName,
            markdown: text
        )
    }

    /// Asks for a name first. The document is created only once the user
    /// confirms, so cancelling leaves nothing behind.
    private func newDocument() {
        shouldRestoreNewDocumentFocus = true
        showingNewDocument = true
    }

    /// Creates the file with the chosen name and opens it.
    private func createDocument(named name: String) {
        focusAfterError = .newDocument
        guard let url = store.createDocument(named: name, contents: "") else { return }
        focusAfterError = nil
        shouldRestoreNewDocumentFocus = false
        store.refresh()
        guard let document = Document(fileURL: url) else { return }
        focusAfterEditor = .document(url)
        openedDocument = DocumentSession(document: document, text: "")
    }

    private func beginRename(_ document: Document) {
        focusAfterError = .document(document.url)
        newName = document.displayName
        renamingDocument = document
    }

    private func commitRename() {
        guard let document = renamingDocument else { return }
        let renamedURL = store.rename(at: document.url, to: newName)
        renamingDocument = nil
        if let renamedURL {
            focusAfterError = nil
            restoreFocus(to: .document(renamedURL))
        }
    }

    private func cancelRename() {
        guard let document = renamingDocument else { return }
        renamingDocument = nil
        restoreFocus(to: .document(document.url))
    }

    private func duplicate(_ document: Document) {
        focusAfterError = .document(document.url)
        if let copy = store.duplicate(document) {
            focusAfterError = nil
            restoreFocus(to: .document(copy.url))
        }
    }

    private func share(_ document: Document) {
        focusAfterError = .document(document.url)
        guard let text = try? store.text(for: document) else { return }
        do {
            let url = try ShareItemBuilder.makeFile(
                title: document.displayName,
                markdown: text,
                format: .markdown
            )
            shareItems = [url]
            focusAfterError = nil
            focusAfterPresentation = .document(document.url)
            showingShare = true
        } catch {
            store.lastError = "Could not prepare \(document.displayName) for sharing. \(error.localizedDescription)"
        }
    }

    private func cancelDelete() {
        guard let document = pendingDeletion else { return }
        pendingDeletion = nil
        restoreFocus(to: .document(document.url))
    }

    private func commitDelete() {
        guard let document = pendingDeletion else { return }
        let before = visibleDocuments
        let deletedIndex = before.firstIndex(of: document)
        let nextURL: URL?

        if let deletedIndex, deletedIndex + 1 < before.count {
            nextURL = before[deletedIndex + 1].url
        } else if let deletedIndex, deletedIndex > 0 {
            nextURL = before[deletedIndex - 1].url
        } else {
            nextURL = nil
        }

        focusAfterError = nextURL.map(LibraryFocus.document) ?? .documentsHeading
        store.delete(document)
        pendingDeletion = nil

        guard store.lastError == nil else { return }
        focusAfterError = nil
        if let nextURL, visibleDocuments.contains(where: { $0.url == nextURL }) {
            restoreFocus(to: .document(nextURL))
        } else {
            restoreFocus(to: .documentsHeading)
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingDocument != nil },
            set: {
                if !$0, renamingDocument != nil {
                    cancelRename()
                }
            }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: {
                if !$0, pendingDeletion != nil {
                    cancelDelete()
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: {
                if !$0, store.lastError != nil {
                    dismissError()
                }
            }
        )
    }

    private var sortFieldBinding: Binding<DocumentSortField> {
        Binding(
            get: { settings.sort.field },
            set: { field in
                var updatedSort = settings.sort
                updatedSort.field = field
                settings.sort = updatedSort
                restoreFocus(to: .sort)
            }
        )
    }

    private var sortDirectionBinding: Binding<SortDirection> {
        Binding(
            get: { settings.sort.direction },
            set: { direction in
                var updatedSort = settings.sort
                updatedSort.direction = direction
                settings.sort = updatedSort
                restoreFocus(to: .sort)
            }
        )
    }

    private var importContentTypes: [UTType] {
        ["md", "markdown", "mdown", "txt"].compactMap {
            UTType(filenameExtension: $0)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let importResult = store.importDocuments(from: urls)
            let target = importResult.imported.first
                .map { LibraryFocus.document($0.url) }
                ?? .importDocument

            if importResult.failedFileNames.isEmpty {
                focusAfterError = nil
                restoreFocus(to: target)
            } else {
                focusAfterError = target
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == NSUserCancelledError {
                restoreFocus(to: .importDocument)
            } else {
                focusAfterError = .importDocument
                store.lastError = "Could not import the selected files. \(error.localizedDescription)"
            }
        }
    }

    private func dismissError() {
        store.lastError = nil
        restoreFocus(to: availableFocus(focusAfterError ?? .documentsHeading))
        focusAfterError = nil
    }

    private func restorePresentationFocus() {
        guard let target = focusAfterPresentation else { return }
        focusAfterPresentation = nil
        restoreFocus(to: availableFocus(target))
    }

    private func availableFocus(_ target: LibraryFocus) -> LibraryFocus {
        if case .document(let url) = target,
           !visibleDocuments.contains(where: { $0.url == url }) {
            return .documentsHeading
        }
        return target
    }

    private func restoreFocus(to target: LibraryFocus) {
        focusedElement = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedElement = target
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            focusedElement = target
        }
    }
}

/// Pairs a document with its loaded text, so the editor receives both at once.
struct DocumentSession: Identifiable, Hashable {
    let document: Document
    let text: String

    var id: URL { document.url }
}

struct RenderedDocumentSession: Identifiable {
    let id = UUID()
    let title: String
    let markdown: String
}
