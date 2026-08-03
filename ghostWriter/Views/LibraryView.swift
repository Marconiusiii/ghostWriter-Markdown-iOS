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

/// Identifies the newest delayed accessibility-focus request. SwiftUI sheets
/// can dismiss close together, so older callbacks must not override a newer,
/// more relevant destination.
struct FocusRestorationRequestGate {
    private(set) var currentID: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    mutating func invalidate() {
        currentID = nil
    }

    func permits(_ id: UUID) -> Bool {
        currentID == id
    }
}

struct LibraryView: View {
    @Environment(DocumentStorage.self) private var storage
    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(DocumentLibraryMetadataStore.self) private var libraryMetadata
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var iCloudMonitor = ICloudDocumentMonitor()
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingRecentlyDeleted = false
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
    @State private var focusRequestGate = FocusRestorationRequestGate()
    @State private var appLaunchActionGate = AppLaunchActionGate()
    @State private var welcomeExperience = WelcomeExperience()
    @State private var showingWelcome = false
    @State private var welcomeDocumentURL: URL?
    @State private var welcomePreparationFailed = false
    @State private var isPreparingWelcomeDocument = false
    @State private var welcomeDismissalAction: WelcomeDismissalAction?
    @State private var searchIndex = DocumentSearchIndex.empty
    @State private var searchAnnounceTask: Task<Void, Never>?
    @State private var pendingDocumentActions:
        [URL: PendingDocumentAction] = [:]
    @State private var downloadTasks:
        [URL: Task<Void, Never>] = [:]
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var focusedElement: LibraryFocus?

    private enum LibraryFocus: Hashable {
        case appHeading
        case settings
        case newDocument
        case importDocument
        case recentlyDeleted
        case sort
        case search
        case documentsHeading
        case document(URL)
    }

    private enum PendingDocumentAction {
        case open
        case render
        case share
        case duplicate
    }

    private enum WelcomeDismissalAction {
        case explore(URL)
        case library
    }

    var body: some View {
        NavigationStack {
            List {
                header
                documentArea
                list
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
                    },
                    onClose: { url in
                        store.refresh()
                        focusAfterEditor = nil
                        restoreFocus(
                            to: availableFocus(
                                .document(documentURL(matching: url))
                            )
                        )
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
        .onAppear {
            if settings.renderSoundEnabled {
                RenderSound.shared.prepare()
            }
            if welcomeExperience.shouldPresent {
                showingWelcome = true
            }
        }
        .onChange(of: settings.renderSoundEnabled) { _, isEnabled in
            if isEnabled {
                RenderSound.shared.prepare()
            }
        }
        .task(id: storage.selectedLocation) {
            await configureSelectedStorage()
        }
        .onChange(of: iCloudMonitor.revision) { _, _ in
            guard storage.selectedLocation == .iCloud else { return }
            store.applyICloudSnapshot(iCloudMonitor.snapshots)
            Task {
                await prepareWelcomeDocumentIfNeeded()
                performAppLaunchBehaviorIfReady()
            }
        }
        .onChange(of: store.documents) { _, _ in
            completePendingDocumentActions()
        }
        .task(id: searchSources) {
            let sources = searchSources
            let buildTask = Task.detached(priority: .utility) {
                DocumentSearchIndex.build(from: sources)
            }
            let rebuilt = await withTaskCancellationHandler {
                await buildTask.value
            } onCancel: {
                buildTask.cancel()
            }
            guard !Task.isCancelled else { return }
            searchIndex = rebuilt
            if !trimmedSearch.isEmpty {
                scheduleSearchAnnouncement()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await configureSelectedStorage()
                }
            }
        }
        .fullScreenCover(isPresented: $showingWelcome, onDismiss: {
            finishWelcomeDismissal()
        }) {
            WelcomeView(
                documentReady: welcomeDocumentURL != nil,
                preparationFailed: welcomePreparationFailed,
                onExplore: exploreWelcomeDocument,
                onContinue: continueFromWelcome
            )
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            restoreFocus(to: .settings)
        }) {
            SettingsView()
        }
        .sheet(isPresented: $showingRecentlyDeleted, onDismiss: {
            restoreFocus(to: .recentlyDeleted)
        }) {
            RecentlyDeletedView()
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
            Text(
                pendingDeletion.map {
                    "\($0.displayName) will move to Recently Deleted, where it can be restored or deleted permanently."
                } ?? ""
            )
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
                .accessibilityFocused($focusedElement, equals: .appHeading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                focusRequestGate.invalidate()
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .accessibilityFocused($focusedElement, equals: .settings)
            .keyboardShortcut(shortcut(",", modifiers: .command))

            // New Document is the primary action, so it comes straight after
            // Settings rather than being buried among the list filters.
            Button {
                newDocument()
            } label: {
                Label("New", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.storageAvailable)
            .accessibilityLabel("New document")
            .accessibilityFocused($focusedElement, equals: .newDocument)
            .keyboardShortcut(shortcut("n", modifiers: .command))

            Button {
                focusRequestGate.invalidate()
                showingImporter = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!store.storageAvailable)
            .accessibilityLabel("Import document")
            .accessibilityHint("Copies markdown or plain-text files into ghostWriter")
            .accessibilityFocused($focusedElement, equals: .importDocument)
            .keyboardShortcut(shortcut("o", modifiers: .command))

            Button {
                focusRequestGate.invalidate()
                showingRecentlyDeleted = true
            } label: {
                HStack {
                    Label("Deleted", systemImage: "trash")
                    Spacer()
                    Text("\(store.recentlyDeletedDocuments.count)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!store.storageAvailable)
            .accessibilityLabel(
                "Deleted, \(recentlyDeletedCountDescription)"
            )
            .accessibilityFocused($focusedElement, equals: .recentlyDeleted)
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
            searchControlLayout {
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

    private var searchControlLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        }
        return AnyLayout(HStackLayout(spacing: 8))
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
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var list: some View {
        if !store.storageAvailable {
            unavailableLibrary
        } else if store.documents.isEmpty {
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
        ForEach(visibleDocuments) { document in
            documentActionLayout {
                Button {
                    open(document)
                } label: {
                    DocumentRow(
                        document: document,
                        isPinned: libraryMetadata.isPinned(document.url)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityFocused(
                    $focusedElement,
                    equals: .document(document.url)
                )
                .accessibilityAction(
                    named: "\(libraryMetadata.isPinned(document.url) ? "Unpin" : "Pin") \(document.displayName)"
                ) {
                    togglePin(document)
                }
                .accessibilityAction(
                    named: "Render \(document.displayName)"
                ) {
                    render(document)
                }
                .accessibilityAction(
                    named: "Share \(document.displayName)"
                ) {
                    share(document)
                }
                .accessibilityAction(
                    named: "Rename \(document.displayName)"
                ) {
                    beginRename(document)
                }
                .accessibilityAction(
                    named: "Duplicate \(document.displayName)"
                ) {
                    duplicate(document)
                }
                .accessibilityAction(
                    named: "Delete \(document.displayName)"
                ) {
                    beginDelete(document)
                }

                if case .failed = document.availability {
                    Button("Retry Download") {
                        retryDownload(document)
                    }
                    .accessibilityLabel(
                        "Retry Download \(document.displayName)"
                    )
                }

                DocumentActionsMenu(
                    document: document,
                    isPinned: libraryMetadata.isPinned(document.url),
                    onTogglePin: { togglePin(document) },
                    onRender: { render(document) },
                    onShare: { share(document) },
                    onRename: { beginRename(document) },
                    onDuplicate: { duplicate(document) },
                    onDelete: { beginDelete(document) }
                )
                .buttonStyle(.bordered)
            }
            // The surrounding stack supplies the horizontal padding, so
            // the list rows do not add their own on top of it.
            .listRowInsets(
                EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
            )
            .listRowBackground(Color.clear)
        }
    }

    private var documentActionLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        }
        return AnyLayout(HStackLayout(spacing: 8))
    }

    // Neither empty state carries a heading. The Documents heading and the
    // count text above already say there is nothing here, so a third element
    // repeating it is just another stop on the way to the New Document button.
    // What remains is the one thing the count does not convey: what to do next.

    private var emptyLibrary: some View {
        Text("Tap New to start writing in markdown.")
            .font(.body)
            .foregroundStyle(Color.ghostMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var unavailableLibrary: some View {
        Text(
            "Your selected document library is unavailable. Open Settings to check iCloud Drive or choose On This Device."
        )
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

    private var searchSources: [DocumentSearchSource] {
        store.documents.map {
            DocumentSearchSource(
                url: $0.url,
                displayName: $0.displayName,
                modified: $0.modified,
                byteCount: $0.byteCount
            )
        }
    }

    private var visibleDocuments: [Document] {
        let query = trimmedSearch
        let filtered: [Document]

        if query.isEmpty {
            filtered = store.documents
        } else {
            filtered = store.documents.filter { document in
                searchIndex.matches(
                    documentURL: document.url,
                    displayName: document.displayName,
                    query: query
                )
            }
        }

        return settings.sort.sorted(filtered, metadata: libraryMetadata)
    }

    private var countDescription: String {
        let count = visibleDocuments.count
        let noun = count == 1 ? "document" : "documents"
        return trimmedSearch.isEmpty ? "\(count) \(noun)" : "Showing \(count) \(noun)"
    }

    private var recentlyDeletedCountDescription: String {
        let count = store.recentlyDeletedDocuments.count
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    // MARK: - Actions

    private func open(_ document: Document) {
        perform(.open, with: document)
    }

    private func openAvailable(_ document: Document) {
        focusRequestGate.invalidate()
        focusAfterError = .document(document.url)
        guard let text = try? store.text(for: document) else { return }
        focusAfterError = nil
        libraryMetadata.recordOpened(document.url)
        focusAfterEditor = .document(document.url)
        openedDocument = DocumentSession(document: document, text: text)
    }

    private func render(_ document: Document) {
        perform(.render, with: document)
    }

    private func renderAvailable(_ document: Document) {
        focusRequestGate.invalidate()
        focusAfterError = .document(document.url)
        guard let text = try? store.text(for: document) else { return }
        focusAfterError = nil
        focusAfterPresentation = .document(document.url)
        if settings.renderSoundEnabled {
            RenderSound.shared.play()
        }
        renderingSession = RenderedDocumentSession(
            title: document.displayName,
            markdown: text
        )
    }

    /// Uses the writer's selected New Document flow. Asking for a title remains
    /// the default; the date option skips the naming sheet and uses the same
    /// safe creation path directly.
    private func newDocument() {
        focusRequestGate.invalidate()
        switch settings.newDocumentCreationMode {
        case .askForTitle:
            shouldRestoreNewDocumentFocus = true
            showingNewDocument = true
        case .useTodaysDate:
            shouldRestoreNewDocumentFocus = false
            createDocument(named: NewDocumentTitle.today())
        }
    }

    /// Creates the file with the chosen name and opens it.
    private func createDocument(named name: String) {
        focusRequestGate.invalidate()
        shouldRestoreNewDocumentFocus = false
        focusAfterError = .newDocument
        Task {
            guard let url = await store.createDocument(
                named: name,
                contents: ""
            ) else { return }
            focusAfterError = nil
            shouldRestoreNewDocumentFocus = false
            store.refresh()
            guard let document = Document(fileURL: url) else { return }
            libraryMetadata.recordOpened(url)
            focusAfterEditor = .document(url)
            openedDocument = DocumentSession(document: document, text: "")
        }
    }

    private func beginRename(_ document: Document) {
        focusRequestGate.invalidate()
        focusAfterError = .document(document.url)
        newName = document.displayName
        renamingDocument = document
    }

    private func commitRename() {
        guard let document = renamingDocument else { return }
        let renamedURL = store.rename(at: document.url, to: newName)
        renamingDocument = nil
        if let renamedURL {
            libraryMetadata.migrateMetadata(
                from: document.url,
                to: renamedURL
            )
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
        perform(.duplicate, with: document)
    }

    private func duplicateAvailable(_ document: Document) {
        focusAfterError = .document(document.url)
        Task {
            if let copy = await store.duplicate(document) {
                focusAfterError = nil
                restoreFocus(to: .document(copy.url))
            }
        }
    }

    private func togglePin(_ document: Document) {
        libraryMetadata.togglePin(for: document.url)
        restoreFocus(to: .document(document.url))
    }

    private func share(_ document: Document) {
        perform(.share, with: document)
    }

    private func shareAvailable(_ document: Document) {
        focusRequestGate.invalidate()
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

    private func beginDelete(_ document: Document) {
        focusRequestGate.invalidate()
        pendingDeletion = document
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
        guard let deletedURL = store.moveToRecentlyDeleted(document) else {
            pendingDeletion = nil
            return
        }
        EditorPositionStore.shared.migratePosition(
            from: document.url,
            to: deletedURL
        )
        libraryMetadata.migrateMetadata(
            from: document.url,
            to: deletedURL
        )
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

    private func shortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> KeyboardShortcut? {
        settings.keyboardShortcutsEnabled
            ? KeyboardShortcut(key, modifiers: modifiers)
            : nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                let importResult = await store.importDocuments(from: urls)
                let target = importResult.imported.first
                    .map { LibraryFocus.document($0.url) }
                    ?? .importDocument

                if importResult.failedFileNames.isEmpty {
                    focusAfterError = nil
                    restoreFocus(to: target)
                } else {
                    focusAfterError = target
                }
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

    private func configureSelectedStorage() async {
        iCloudMonitor.stop()

        let directory = await storage.prepareCurrentLocation()
        guard storage.selectedLocation == .iCloud else {
            downloadTasks.values.forEach { $0.cancel() }
            downloadTasks = [:]
            pendingDocumentActions = [:]
            store.clearICloudSnapshot()
            store.useDirectory(
                directory,
                usesICloudStorage: false
            )
            await prepareWelcomeDocumentIfNeeded()
            performAppLaunchBehaviorIfReady()
            return
        }

        store.useDirectory(
            directory,
            usesICloudStorage: true
        )
        if let directory {
            iCloudMonitor.start(rootDirectory: directory)
        } else {
            await prepareWelcomeDocumentIfNeeded()
        }
        performAppLaunchBehaviorIfReady()
    }

    private func performAppLaunchBehaviorIfReady() {
        guard !appLaunchActionGate.hasPerformed else { return }
        guard !welcomeExperience.shouldPresent else { return }

        if storage.selectedLocation == .iCloud,
           case .available = storage.iCloudAvailability,
           iCloudMonitor.revision == 0,
           settings.appLaunchBehavior == .openLastDocument {
            // Remote-only documents do not necessarily appear in the local
            // directory until the metadata query completes its first gather.
            return
        }

        guard appLaunchActionGate.begin() else { return }

        switch settings.appLaunchBehavior {
        case .showLibrary:
            return
        case .startNewDocument:
            guard store.storageAvailable else { return }
            newDocument()
        case .openLastDocument:
            guard store.storageAvailable,
                  let document = libraryMetadata.mostRecentlyOpenedDocument(
                    in: store.documents
                  ) else {
                return
            }
            open(document)
        }
    }

    private func prepareWelcomeDocumentIfNeeded() async {
        guard !isPreparingWelcomeDocument else { return }
        guard !welcomeExperience.hasInstalledDocument
                || welcomeExperience.shouldPresent else {
            return
        }
        guard store.storageAvailable else {
            if welcomeExperience.shouldPresent {
                welcomePreparationFailed = true
            }
            return
        }

        isPreparingWelcomeDocument = true
        defer { isPreparingWelcomeDocument = false }
        welcomePreparationFailed = false
        let url = await welcomeExperience.installDocumentIfNeeded(
            in: store,
            markdown: try WelcomeDocument.bundledMarkdown()
        )
        welcomeDocumentURL = url
        if url == nil, welcomeExperience.shouldPresent {
            welcomePreparationFailed = true
        }
    }

    private func exploreWelcomeDocument() {
        guard let welcomeDocumentURL else { return }
        welcomeExperience.complete()
        _ = appLaunchActionGate.begin()
        welcomeDismissalAction = .explore(welcomeDocumentURL)
        showingWelcome = false
    }

    private func continueFromWelcome() {
        welcomeExperience.complete()
        _ = appLaunchActionGate.begin()
        welcomeDismissalAction = .library
        showingWelcome = false
    }

    private func finishWelcomeDismissal() {
        let action = welcomeDismissalAction
        welcomeDismissalAction = nil

        switch action {
        case .explore(let url):
            store.refresh()
            guard let document = store.documents.first(where: {
                $0.url.standardizedFileURL == url.standardizedFileURL
            }) else {
                restoreFocus(to: .appHeading)
                return
            }
            open(document)
        case .library:
            restoreFocus(to: .appHeading)
        case nil:
            break
        }
    }

    private func perform(
        _ action: PendingDocumentAction,
        with document: Document
    ) {
        guard document.availability.isAvailable else {
            pendingDocumentActions[
                document.url.standardizedFileURL
            ] = action
            beginDownload(document)
            return
        }
        performAvailable(action, with: document)
    }

    private func retryDownload(_ document: Document) {
        let url = document.url.standardizedFileURL
        if pendingDocumentActions[url] == nil {
            pendingDocumentActions[url] = .open
        }
        beginDownload(document)
    }

    private func beginDownload(_ document: Document) {
        let url = document.url.standardizedFileURL
        guard downloadTasks[url] == nil else { return }

        downloadTasks[url] = Task {
            let succeeded = await store.requestDownload(for: document)
            downloadTasks[url] = nil
            if succeeded {
                completePendingDocumentActions()
            }
        }
    }

    private func completePendingDocumentActions() {
        let ready = pendingDocumentActions.compactMap {
            url, action -> (URL, PendingDocumentAction, Document)? in
            guard let document = store.documents.first(where: {
                $0.url.standardizedFileURL == url
            }), document.availability.isAvailable else {
                return nil
            }
            return (url, action, document)
        }

        for (url, action, document) in ready {
            pendingDocumentActions[url] = nil
            performAvailable(action, with: document)
        }
    }

    private func performAvailable(
        _ action: PendingDocumentAction,
        with document: Document
    ) {
        switch action {
        case .open:
            openAvailable(document)
        case .render:
            renderAvailable(document)
        case .share:
            shareAvailable(document)
        case .duplicate:
            duplicateAvailable(document)
        }
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

    private func documentURL(matching url: URL) -> URL {
        store.documents.first {
            $0.url.standardizedFileURL == url.standardizedFileURL
        }?.url ?? url
    }

    private func restoreFocus(to target: LibraryFocus) {
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
