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
    @State private var searchAnnounceTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

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
                EditorView(document: session.document, initialText: session.text)
            }
            // Saving no longer republishes the store's list — that churn was
            // what let the editor lose track of its file — so the library
            // re-reads the folder when it comes back into view.
            .onChange(of: openedDocument) { _, value in
                if value == nil { store.refresh() }
            }
            .onChange(of: searchText) { _, _ in
                scheduleSearchAnnouncement()
            }
        }
        .onAppear { store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingNewDocument) {
            NewDocumentView { name in
                createDocument(named: name)
            }
        }
        .fullScreenCover(item: $renderingSession) { session in
            RenderedHTMLView(
                title: session.title,
                markdown: session.markdown
            )
        }
        .sheet(isPresented: $showingShare) { ShareSheet(items: shareItems) }
        .alert("Rename Document", isPresented: renameBinding) {
            TextField("Name", text: $newName)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { renamingDocument = nil }
            Button("Rename") { commitRename() }
        } message: {
            Text("Enter a new name for this document.")
        }
        .alert("Delete Document?", isPresented: deleteBinding) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let document = pendingDeletion { store.delete(document) }
                pendingDeletion = nil
            }
        } message: {
            Text(pendingDeletion.map { "\($0.displayName) will be deleted. This cannot be undone." } ?? "")
        }
        .alert("ghostWriter Error", isPresented: errorBinding) {
            Button("OK") { store.lastError = nil }
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

        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Two clearly separated groups under their own headings, rather than two
    /// pickers whose options run together as one undifferentiated list.
    private var sortMenu: some View {
        @Bindable var settings = settings

        return Menu {
            Section("Sort By") {
                Picker("Sort By", selection: $settings.sort.field) {
                    ForEach(DocumentSortField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Sort Order") {
                Picker("Sort Order", selection: $settings.sort.direction) {
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
        guard let text = try? store.text(for: document) else { return }
        openedDocument = DocumentSession(document: document, text: text)
    }

    private func render(_ document: Document) {
        guard let text = try? store.text(for: document) else { return }
        renderingSession = RenderedDocumentSession(
            title: document.displayName,
            markdown: text
        )
    }

    /// Asks for a name first. The document is created only once the user
    /// confirms, so cancelling leaves nothing behind.
    private func newDocument() {
        showingNewDocument = true
    }

    /// Creates the file with the chosen name and opens it.
    private func createDocument(named name: String) {
        guard let url = store.createDocument(named: name, contents: "") else { return }
        store.refresh()
        guard let document = Document(fileURL: url) else { return }
        openedDocument = DocumentSession(document: document, text: "")
    }

    private func beginRename(_ document: Document) {
        newName = document.displayName
        renamingDocument = document
    }

    private func commitRename() {
        guard let document = renamingDocument else { return }
        store.rename(at: document.url, to: newName)
        renamingDocument = nil
    }

    private func duplicate(_ document: Document) {
        store.duplicate(document)
    }

    private func share(_ document: Document) {
        guard let text = try? store.text(for: document) else { return }
        do {
            let url = try ShareItemBuilder.makeFile(
                title: document.displayName,
                markdown: text,
                format: .markdown
            )
            shareItems = [url]
            showingShare = true
        } catch {
            store.lastError = "Could not prepare \(document.displayName) for sharing. \(error.localizedDescription)"
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingDocument != nil },
            set: { if !$0 { renamingDocument = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
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
