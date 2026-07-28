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

struct LibraryView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var renderingDocument: Document?
    @State private var renamingDocument: Document?
    @State private var pendingDeletion: Document?
    @State private var newName = ""
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var openedDocument: DocumentSession?
    @State private var draftDocument: DraftDocument?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                controls
                documentArea
            }
            .background(Color.pageBackground)
            // The heading below is the screen's title, so the bar is hidden
            // rather than duplicating it above the content.
            .navigationBarHidden(true)
            .navigationDestination(item: $openedDocument) { session in
                EditorView(document: session.document, initialText: session.text)
            }
            .navigationDestination(item: $draftDocument) { draft in
                EditorView(draftNamed: draft.suggestedName)
            }
            // Saving no longer republishes the store's list — that churn was
            // what let the editor lose track of its file — so the library
            // re-reads the folder when it comes back into view.
            .onChange(of: openedDocument) { _, value in
                if value == nil { store.refresh() }
            }
            .onChange(of: draftDocument) { _, value in
                if value == nil { store.refresh() }
            }
        }
        .onAppear { store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .fullScreenCover(item: $renderingDocument) { document in
            RenderedHTMLView(
                title: document.displayName,
                markdown: store.text(for: document)
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
    }

    // MARK: - Header

    /// First element on the screen and first in code. A real heading, so the
    /// heading rotor finds it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ghostWriter Markdown")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.ghostAccent)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Settings comes after the heading, in code and on screen.
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Controls

    /// Sort and search sit together, directly after Settings and before the
    /// list they act on.
    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                sortMenu
                Spacer(minLength: 0)
                Button {
                    newDocument()
                } label: {
                    Label("New Document", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
            }

            searchField
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var sortMenu: some View {
        @Bindable var settings = settings

        return Menu {
            Picker("Sort By", selection: $settings.sort.field) {
                ForEach(DocumentSortField.allCases) { field in
                    Text(field.label).tag(field)
                }
            }
            Picker("Order", selection: $settings.sort.direction) {
                ForEach(SortDirection.allCases) { direction in
                    Text(direction.label(for: settings.sort.field)).tag(direction)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Sort")
        .accessibilityValue(settings.sort.spokenDescription)
    }

    /// An ordinary text field rather than `.searchable`, so it stays where it
    /// is written: above the list, not below it.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ghostMuted)
                .accessibilityHidden(true)

            TextField("Search documents", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search documents")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ghostMuted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.ghostBorder, lineWidth: 1)
        )
    }

    // MARK: - List

    @ViewBuilder
    private var documentArea: some View {
        if store.documents.isEmpty {
            emptyLibrary
        } else if visibleDocuments.isEmpty {
            noSearchResults
        } else {
            documentList
        }
    }

    private var documentList: some View {
        List {
            Section {
                ForEach(visibleDocuments) { document in
                    Button {
                        open(document)
                    } label: {
                        DocumentRow(
                            document: document,
                            onRender: { renderingDocument = document },
                            onShare: { share(document) },
                            onRename: { beginRename(document) },
                            onDelete: { pendingDeletion = document }
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletion = document
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            beginRename(document)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            renderingDocument = document
                        } label: {
                            Label("Render", systemImage: "doc.richtext")
                        }
                        Button {
                            share(document)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } header: {
                Text(countDescription)
            }
        }
        .listStyle(.plain)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No Documents")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Tap New Document to start writing in markdown.")
                .font(.body)
                .foregroundStyle(Color.ghostMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var noSearchResults: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No Results")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("No documents match \(searchText).")
                .font(.body)
                .foregroundStyle(Color.ghostMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Data

    private var visibleDocuments: [Document] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [Document]

        if query.isEmpty {
            filtered = store.documents
        } else {
            filtered = store.documents.filter { document in
                if document.displayName.localizedCaseInsensitiveContains(query) { return true }
                return store.text(for: document).localizedCaseInsensitiveContains(query)
            }
        }

        return settings.sort.sorted(filtered)
    }

    private var countDescription: String {
        let count = visibleDocuments.count
        return count == 1 ? "1 document" : "\(count) documents"
    }

    // MARK: - Actions

    private func open(_ document: Document) {
        openedDocument = DocumentSession(
            document: document,
            text: store.text(for: document)
        )
    }

    /// Opens the editor on a blank draft. Nothing is written to disk until the
    /// user actually types something, so the library is never littered with
    /// empty "Untitled" files from a mis-tap.
    private func newDocument() {
        draftDocument = DraftDocument(suggestedName: "Untitled")
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

    private func share(_ document: Document) {
        guard let url = ShareItemBuilder.makeFile(
            title: document.displayName,
            markdown: store.text(for: document),
            format: .markdown
        ) else { return }
        shareItems = [url]
        showingShare = true
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
}

/// Pairs a document with its loaded text, so the editor receives both at once.
struct DocumentSession: Identifiable, Hashable {
    let document: Document
    let text: String

    var id: URL { document.url }
}

/// A document that does not exist on disk yet.
struct DraftDocument: Identifiable, Hashable {
    let suggestedName: String
    var id: String { suggestedName }
}
