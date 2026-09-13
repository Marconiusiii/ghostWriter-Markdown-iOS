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
    @Environment(DocumentStorage.self) private var storage
    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(DocumentLibraryMetadataStore.self) private var libraryMetadata
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var iCloudMonitor = ICloudDocumentMonitor()
    @State private var searchText = ""
    @State private var libraryEditMode = EditMode.inactive
    @State private var countFolder: LibraryFolder?
    @State private var compilationFolder: LibraryFolder?
    @State private var showingSettings = false
    @State private var showingRecentlyDeleted = false
    @State private var renderingSession: RenderedDocumentSession?
    // Keep the originating row stable through the native dismissal transition.
    @State private var renderingDocumentURL: URL?
    @State private var renamingDocument: Document?
    @State private var pendingDeletion: Document?
    @State private var pendingRename: LibraryItem?
    @State private var newName = ""
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var openedDocument: DocumentSession?
    @State private var documentPath: [URL] = []
    @State private var showingNewDocument = false
    @State private var showingNewFolder = false
    @State private var showingImporter = false
    @State private var showingPowerPointImportOptions = false
    @State private var pendingImportURLs: [URL] = []
    @State private var pendingImportDestination: URL?
    @State private var pendingImportOptions: PowerPointImportOptions?
    @State private var pendingImportAccess: [URL] = []
    @State private var isImporting = false
    @State private var importNotice: String?
    @State private var currentFolderURL: URL?
    @State private var configuredStorageLocation: DocumentStorageChoice?
    @State private var renamingFolder: LibraryFolder?
    @State private var pendingFolderDeletion: LibraryFolder?
    @State private var movingItem: LibraryItem?
    @State private var appLaunchActionGate = AppLaunchActionGate()
    @State private var welcomeExperience = WelcomeExperience()
    @State private var showingWelcome = false
    @State private var pendingHelpManual = false
    @State private var preparingHelpManual = false
    @State private var welcomeDocumentURL: URL?
    @State private var welcomePreparationFailed = false
    @State private var isPreparingWelcomeDocument = false
    @State private var welcomeDismissalAction: WelcomeDismissalAction?
    @State private var searchIndex = DocumentSearchIndex.empty
    @State private var searchIndexRevision = 0
    @State private var libraryPresentation = LibraryPresentationSnapshot.empty
    @State private var searchAnnounceTask: Task<Void, Never>?
    @State private var libraryActivityTask: Task<Void, Never>?
    @State private var documentOpenTask: Task<Void, Never>?
    @State private var openingDocumentURL: URL?
    @State private var pendingDocumentActions:
        [URL: PendingDocumentAction] = [:]
    @State private var downloadTasks:
        [URL: Task<Void, Never>] = [:]
    @FocusState private var searchFocused: Bool

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

    private struct LibraryPresentationIdentity: Equatable {
        let storeRevision: Int
        let metadataRevision: Int
        let searchIndexRevision: Int
        let directory: URL
        let query: String
        let sort: DocumentSort
        let calendarDay: Date
    }

    var body: some View {
        NavigationStack(path: $documentPath) {
            List {
                header
                if isImporting { ProgressView("Importing documents…") }
                documentArea
                if currentFolderURL == nil,
                   !store.documents.contains(where: { $0.url.standardizedFileURL == HelpManualDocument.libraryURL(in: store.directory).standardizedFileURL }),
                   trimmedSearch.isEmpty || "ghostWriter Help Manual".localizedCaseInsensitiveContains(trimmedSearch) {
                    Button("ghostWriter Help Manual") { openHelpManualFromLibrary() }
                        .disabled(preparingHelpManual)
                        .accessibilityLabel("ghostWriter Help Manual")
                }
                if canReorder || libraryEditMode.isEditing {
                    FileOrderEditButton(editMode: $libraryEditMode)
                }
                list
            }
            .environment(\.editMode, $libraryEditMode)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            // The heading below is the screen's title, so the bar is hidden
            // rather than duplicating it above the content.
            .navigationBarHidden(true)
            .navigationDestination(for: URL.self) { url in
                LibraryEditorDestination(url: url, preparedSession: openedDocument)
            }

            .onChange(of: documentPath) { _, path in
                if !path.isEmpty {
                    suspendLibraryActivityForDocumentPresentation()
                } else {
                    openedDocument = nil
                    libraryActivityTask = Task {
                        await resumeLibraryActivityAfterDocumentPresentation()
                        guard !Task.isCancelled else { return }
                        guard libraryIsActive else { return }
                    }
                }
            }
            .onChange(of: searchText) { _, _ in
                libraryEditMode = .inactive
                scheduleSearchAnnouncement()
            }
        }
        .onChange(of: currentDirectory) { _, _ in libraryEditMode = .inactive }
        .onChange(of: currentSort) { _, _ in libraryEditMode = .inactive }
        .focusedSceneValue(\.newLibraryDocument, canCreateUsingCommand ? { newDocument() } : nil)
        .sheet(item: $countFolder) { folder in FolderCountView(folder: folder) }
        .sheet(item: $compilationFolder) { folder in
            CompilationExportView(directory: folder.url)
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
        .task(id: libraryPresentationIdentity) {
            guard libraryIsActive else { return }
            rebuildLibraryPresentation()
        }
        .onChange(of: iCloudMonitor.revision) { _, _ in
            guard libraryIsActive,
                  storage.selectedLocation == .iCloud else { return }
            libraryActivityTask?.cancel()
            libraryActivityTask = Task {
                await store.applyICloudSnapshotAsynchronously(
                    iCloudMonitor.snapshots
                )
                guard !Task.isCancelled, libraryIsActive else { return }
                await prepareWelcomeDocumentIfNeeded()
                performAppLaunchBehaviorIfReady()
            }
        }
        .onChange(of: store.documents) { _, _ in
            completePendingDocumentActions()
        }
        .task(id: libraryIsActive ? searchSources : []) {
            guard libraryIsActive else { return }
            let sources = searchSources
            let buildTask = Task.detached(priority: .utility) {
                DocumentSearchIndex.build(from: sources)
            }
            let rebuilt = await withTaskCancellationHandler {
                await buildTask.value
            } onCancel: {
                buildTask.cancel()
            }
            guard !Task.isCancelled, libraryIsActive else { return }
            searchIndex = rebuilt
            searchIndexRevision &+= 1
            if !trimmedSearch.isEmpty {
                scheduleSearchAnnouncement()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, libraryIsActive {
                libraryActivityTask?.cancel()
                libraryActivityTask = Task {
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
            if pendingHelpManual {
                pendingHelpManual = false
                openHelpManualFromLibrary()
            }
        }) {
            SettingsView(onOpenHelpManual: { pendingHelpManual = true })
        }
        .sheet(isPresented: $showingRecentlyDeleted) {
            RecentlyDeletedView()
        }
        .sheet(isPresented: $showingNewDocument) {
            NewDocumentView { name in
                createDocument(named: name)
            }
        }
        .sheet(isPresented: $showingNewFolder) {
            NewFolderView { name in
                createFolder(named: name)
            }
        }
        .sheet(item: $movingItem) { item in
            MoveLibraryItemView(
                itemName: item.displayName,
                rootDirectory: store.directory,
                folders: store.folders,
                excludedURLs: excludedMoveDestinations(for: item),
                onMove: { destination in move(item, to: destination) }
            )
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: shareItems)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingPowerPointImportOptions, onDismiss: finishPowerPointImportOptions) {
            PowerPointImportOptionsView(options: settings.powerPointImportOptions) { options in
                settings.powerPointImportOptions = options
                pendingImportOptions = options
            }
        }
        .sheet(item: $renamingDocument, onDismiss: finishRenamePresentation) { item in
            RenameItemView(title: "Rename Document", fieldLabel: "Document name", name: $newName,
                onCancel: { renamingDocument = nil },
                onRename: { pendingRename = .document(item); renamingDocument = nil })
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
        .sheet(item: $renamingFolder, onDismiss: finishRenamePresentation) { item in
            RenameItemView(title: "Rename Folder", fieldLabel: "Folder name", name: $newName,
                onCancel: { renamingFolder = nil },
                onRename: { pendingRename = .folder(item); renamingFolder = nil })
        }
        .alert("Delete Folder?", isPresented: folderDeleteBinding) {
            Button("Cancel", role: .cancel) { cancelFolderDelete() }
            Button("Delete", role: .destructive) { commitFolderDelete() }
        } message: {
            Text(
                pendingFolderDeletion.map {
                    "\($0.displayName) and everything inside it will move to Recently Deleted."
                } ?? ""
            )
        }
        .alert("ghostWriter Error", isPresented: errorBinding) {
            Button("OK") { dismissError() }
        } message: {
            Text(store.lastError ?? "An unknown error occurred.")
        }
        .alert("Document Import", isPresented: importNoticeBinding) {
            Button("OK") { dismissImportNotice() }
        } message: {
            Text(importNotice ?? "The documents were imported.")
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
            .keyboardShortcut(shortcut(",", modifiers: .command))

            // New Document is the primary action, so it comes straight after
            // Settings rather than being buried among the list filters.
            Button {
                newDocument()
            } label: {
                Label("New", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .ghostProminentButtonStyle()
            .controlSize(.large)
            .disabled(!store.storageAvailable)
            .accessibilityLabel("New document")

            Button {
                showingNewFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!store.storageAvailable)

            Button {
                showingImporter = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!store.storageAvailable)
            .accessibilityLabel("Import document")
            .disabled(isImporting)
            .accessibilityHint("Copies Markdown, plain-text, Word, or PowerPoint documents into ghostWriter")
            .keyboardShortcut(shortcut("o", modifiers: .command))

            Button {
                showingRecentlyDeleted = true
            } label: {
                HStack {
                    Label("Deleted", systemImage: "trash")
                    Spacer()
                    Text("\(store.recentlyDeletedItems.count)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!store.storageAvailable)
            .accessibilityLabel(
                "Deleted, \(recentlyDeletedCountDescription)"
            )
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

            if currentSort.field != .manual {
                Section("Sort Order") {
                    Picker("Sort Order", selection: sortDirectionBinding) {
                        ForEach(SortDirection.allCases) { direction in
                            Text(direction.label(for: currentSort.field)).tag(direction)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered)
        .accessibilityValue(currentSort.spokenDescription)
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
                .accessibilityHint("Clears the search and shows all items")
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

        announceCount(prefix: "Showing")
    }

    /// Waits for typing to settle, then says how many documents match. Firing
    /// on every keystroke would talk over the letters being typed.
    private func scheduleSearchAnnouncement() {
        searchAnnounceTask?.cancel()
        guard libraryIsActive else { return }
        searchAnnounceTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, libraryIsActive else { return }
            announceCount(prefix: "Showing")
        }
    }

    private func toggleCompilationInclusion(for url: URL) {
        let confirmation = libraryMetadata.toggleDefaultInclusion(for: url)
        UIAccessibility.post(notification: .announcement, argument: confirmation)
    }

    private func announceCount(prefix: String) {
        let count = visibleDocuments.count + visibleFolders.count
        let noun = count == 1 ? "item" : "items"
        UIAccessibility.post(notification: .announcement, argument: "\(prefix) \(count) \(noun)")
    }

    // MARK: - List

    /// "Documents" is the heading. The count is ordinary text beneath the
    /// search field, where it doubles as the search result announcement.
    private var documentArea: some View {
        // Separate native List rows keep Sort independent of changing headings,
        // counts, and search content during a selection update.
        Group {
            Text(currentFolderHeading)
                .font(.title2.bold())
                .foregroundStyle(Color.ghostAccent)
                .accessibilityAddTraits(.isHeader)
                .contextMenu {
                    if let currentFolderURL {
                        Button("Total Word Count") { countFolder = LibraryFolder(url: currentFolderURL) }
                        Button(libraryMetadata.inclusionActionLabel(for: currentFolderURL)) { toggleCompilationInclusion(for: currentFolderURL) }
                        Button("Export Compilation…") {
                            compilationFolder = LibraryFolder(url: currentFolderURL)
                        }
                    }
                }
                .accessibilityActions {
                    if let currentFolderURL {
                        Button("Total Word Count") { countFolder = LibraryFolder(url: currentFolderURL) }
                        Button(libraryMetadata.inclusionActionLabel(for: currentFolderURL)) { toggleCompilationInclusion(for: currentFolderURL) }
                        Button("Export Compilation…") {
                            compilationFolder = LibraryFolder(url: currentFolderURL)
                        }
                    }
                }

            if currentFolderURL != nil {
                Button("Back to \(parentFolderName)") {
                    navigateBack()
                }
                .buttonStyle(.bordered)
            }

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
        } else if libraryPresentation.currentItemCount == 0 {
            EmptyView()
        } else if libraryPresentation.documents.isEmpty
                    && libraryPresentation.folders.isEmpty {
            noSearchResults
        } else {
            documentList
        }
    }

    @ViewBuilder
    private var documentList: some View {
        if currentSort.field == .manual {
            manualRows(pinnedManualItems)
            manualRows(unpinnedManualItems)
        } else {
            // No section header here: the count heading above this list is the
            // heading for it, and repeating it would be a second announcement of
            // the same thing.
            ForEach(libraryPresentation.folders) { presentation in
                libraryFolderRow(presentation)
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
                )
                .listRowBackground(Color.clear)
            }

            ForEach(libraryPresentation.documents) { presentation in
                libraryDocumentRow(presentation)
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    private var canReorder: Bool {
        currentSort.field == .manual && trimmedSearch.isEmpty
            && libraryPresentation.currentItemCount > 1
    }

    private var manualItems: [LibraryItem] {
        let items = libraryPresentation.folders.map { LibraryItem.folder($0.folder) }
            + libraryPresentation.documents.map { LibraryItem.document($0.document) }
        let byURL = Dictionary(uniqueKeysWithValues: items.map { ($0.url, $0) })
        return libraryMetadata.manuallyOrdered(items.map(\.url)).compactMap { byURL[$0] }
    }

    private var pinnedManualItems: [LibraryItem] {
        manualItems.filter { !$0.isFolder && libraryMetadata.isPinned($0.url) }
    }

    private var unpinnedManualItems: [LibraryItem] {
        manualItems.filter { $0.isFolder || !libraryMetadata.isPinned($0.url) }
    }

    private func manualRows(_ items: [LibraryItem]) -> some View {
        ForEach(items) { item in
            Group {
                switch item {
                case .folder(let folder):
                    if let row = libraryPresentation.folders.first(where: { $0.id == folder.id }) {
                        libraryFolderRow(row)
                    }
                case .document(let document):
                    if let row = libraryPresentation.documents.first(where: { $0.id == document.id }) {
                        libraryDocumentRow(row)
                    }
                }
            }
            .moveDisabled(!canReorder)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
        }
        .onMove { offsets, destination in
            guard canReorder else { return }
            var reordered = items
            reordered.move(fromOffsets: offsets, toOffset: destination)
            let movedIDs = Set(items.map(\.id))
            var iterator = reordered.makeIterator()
            let merged = manualItems.map { movedIDs.contains($0.id) ? iterator.next()! : $0 }
            libraryMetadata.setManualOrder(merged.map(\.url), in: currentDirectory)
            rebuildLibraryPresentation()
        }
    }

    private func libraryFolderRow(
        _ presentation: LibraryFolderPresentation
    ) -> some View {
        let folder = presentation.folder
        let primaryRow = Button {
            open(folder)
        } label: {
            FolderRow(
                folder: folder,
                itemCount: presentation.itemCount
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)

        let accessibleRow = primaryRow
            .accessibilityAction(named: "Total Word Count") { countFolder = folder }
            .accessibilityAction(named: libraryMetadata.inclusionActionLabel(for: folder.url)) { toggleCompilationInclusion(for: folder.url) }
            .accessibilityAction(named: "Export Compilation…") {
                compilationFolder = folder
            }
            .accessibilityAction(named: "Rename") {
                beginRename(folder)
            }
            .accessibilityAction(named: "Move") {
                beginMove(.folder(folder))
            }
            .accessibilityAction(named: "Delete") {
                beginDelete(folder)
            }

        let leadingSwipeRow = accessibleRow
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if !voiceOverEnabled {
                    Button {
                        beginRename(folder)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(Color.controlFill)
                }
            }

        let swipeRow = leadingSwipeRow
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !voiceOverEnabled {
                    Button(role: .destructive) {
                        beginDelete(folder)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        beginMove(.folder(folder))
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .tint(Color.controlFill)
                }
            }

        return swipeRow.contextMenu {
            Button("Total Word Count") { countFolder = folder }
            Button(libraryMetadata.inclusionActionLabel(for: folder.url)) { toggleCompilationInclusion(for: folder.url) }
            Button("Export Compilation…") { compilationFolder = folder }
            Button {
                beginRename(folder)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                beginMove(.folder(folder))
            } label: {
                Label("Move", systemImage: "folder")
            }

            Button(role: .destructive) {
                beginDelete(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func libraryDocumentRow(
        _ presentation: LibraryDocumentPresentation
    ) -> some View {
        let document = presentation.document
        let primaryRow = NavigationLink(value: document.url) {
            DocumentRow(presentation: presentation)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)

        let commonActions = primaryRow
            .accessibilityActions {
                if voiceOverEnabled {
                    Button(presentation.isPinned ? "Unpin" : "Pin") {
                        togglePin(document)
                    }
                    if case .failed = document.availability {
                        Button("Retry Download") {
                            retryDownload(document)
                        }
                    }
                }
                if store.usesICloudStorage {
                    Button("Sync") {
                        synchronize(document)
                    }
                }
            }
            .accessibilityAction(named: libraryMetadata.inclusionActionLabel(for: document.url)) { toggleCompilationInclusion(for: document.url) }
            .accessibilityAction(named: "Render") {
                render(document)
            }
            .accessibilityAction(named: "Share") {
                share(document)
            }
            .accessibilityAction(named: "Rename") {
                beginRename(document)
            }

        let accessibleRow = commonActions
            .accessibilityAction(named: "Move") {
                beginMove(.document(document))
            }
            .accessibilityAction(named: "Duplicate") {
                duplicate(document)
            }
            .accessibilityAction(named: "Delete") {
                beginDelete(document)
            }

        let leadingSwipeRow = accessibleRow
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if !voiceOverEnabled {
                    Button {
                        togglePin(document)
                    } label: {
                        Label(
                            presentation.isPinned ? "Unpin" : "Pin",
                            systemImage: presentation.isPinned ? "pin.slash" : "pin"
                        )
                    }
                    .tint(Color.controlFill)

                    if case .failed = document.availability {
                        Button {
                            retryDownload(document)
                        } label: {
                            Label("Retry Download", systemImage: "arrow.clockwise")
                        }
                        .tint(Color.controlFill)
                    }
                }
            }

        let swipeRow = leadingSwipeRow
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !voiceOverEnabled {
                    Button(role: .destructive) {
                        beginDelete(document)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        share(document)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(Color.controlFill)
                }
            }

        return swipeRow.contextMenu {
            Button(libraryMetadata.inclusionActionLabel(for: document.url)) { toggleCompilationInclusion(for: document.url) }
            if store.usesICloudStorage {
                Button {
                    synchronize(document)
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }

                Divider()
            }

            if case .failed = document.availability {
                Button {
                    retryDownload(document)
                } label: {
                    Label("Retry Download", systemImage: "arrow.clockwise")
                }

                Divider()
            }

            Button {
                togglePin(document)
            } label: {
                Label(
                    presentation.isPinned ? "Unpin" : "Pin",
                    systemImage: presentation.isPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Button {
                render(document)
            } label: {
                Label("Render", systemImage: "doc.richtext")
            }

            Button {
                share(document)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                beginRename(document)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                beginMove(.document(document))
            } label: {
                Label("Move", systemImage: "folder")
            }

            Button {
                duplicate(document)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                beginDelete(document)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .fullScreenCover(item: Binding(
            get: { renderingDocumentURL == document.url ? renderingSession : nil },
            set: { session in
                guard renderingDocumentURL == document.url else { return }
                renderingSession = session
            }
        ), onDismiss: {
            finishLibraryRendering(from: document.url)
        }) { session in
            RenderedHTMLView(
                title: session.title,
                markdown: session.markdown,
                documentURL: session.documentURL
            )
        }
    }

    private var libraryIsActive: Bool {
        documentPath.isEmpty && renderingDocumentURL == nil
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
        Text("No items match \(trimmedSearch).")
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

    private var currentSort: DocumentSort {
        libraryMetadata.sort(in: currentDirectory, fallback: settings.sort)
    }

    private var currentDirectory: URL {
        currentFolderURL ?? store.directory
    }

    private var libraryPresentationIdentity: LibraryPresentationIdentity {
        LibraryPresentationIdentity(
            storeRevision: store.libraryPresentationRevision,
            metadataRevision: libraryMetadata.libraryPresentationRevision,
            searchIndexRevision: searchIndexRevision,
            directory: currentDirectory,
            query: trimmedSearch,
            sort: currentSort,
            calendarDay: Calendar.current.startOfDay(for: .now)
        )
    }

    private var visibleDocuments: [Document] {
        libraryPresentation.documents.map(\.document)
    }

    private var visibleFolders: [LibraryFolder] {
        libraryPresentation.folders.map(\.folder)
    }

    private func rebuildLibraryPresentation() {
        guard libraryIsActive else { return }
        let updated = LibraryPresentationSnapshot.build(
            documents: store.documents,
            folders: store.folders,
            currentDirectory: currentDirectory,
            query: trimmedSearch,
            searchIndex: searchIndex,
            sort: currentSort,
            metadata: libraryMetadata
        )
        if updated != libraryPresentation { libraryPresentation = updated }
    }

    private var currentFolderHeading: String {
        currentFolderURL?.lastPathComponent ?? "Documents"
    }

    private var parentFolderName: String {
        guard let currentFolderURL else { return String(localized: "Documents") }
        let parent = currentFolderURL.deletingLastPathComponent()
        return parent.standardizedFileURL == store.directory.standardizedFileURL
            ? "Documents"
            : parent.lastPathComponent
    }

    private var countDescription: String {
        let count = visibleDocuments.count + visibleFolders.count
        let noun = count == 1 ? "item" : "items"
        return trimmedSearch.isEmpty ? "\(count) \(noun)" : "Showing \(count) \(noun)"
    }

    private var recentlyDeletedCountDescription: String {
        let count = store.recentlyDeletedItems.count
        return count == 1
            ? String(localized: "1 item")
            : String(localized: "\(count) items")
    }

    // MARK: - Actions

    private func openHelpManualFromLibrary() {
        guard !preparingHelpManual else { return }
        preparingHelpManual = true
        Task {
            defer { preparingHelpManual = false }
            do {
                let url = try await HelpManualDocument.installIfNeeded(in: store)
                await store.refreshAsynchronously()
                guard let document = store.documents.first(where: { $0.url == url }) ?? Document(fileURL: url) else {
                    throw WordThemeError.invalid("The ghostWriter Help Manual could not be opened.")
                }
                currentFolderURL = nil
                searchText = ""
                searchFocused = false
                libraryEditMode = .inactive
                rebuildLibraryPresentation()
                open(document)
            } catch { store.lastError = error.localizedDescription }
        }
    }

    private func open(_ document: Document) {
        perform(.open, with: document)
    }

    private func openAvailable(_ document: Document) {
        let url = document.url.standardizedFileURL
        guard openingDocumentURL != url else { return }
        documentOpenTask?.cancel()

        openingDocumentURL = url
        documentOpenTask = Task {
            guard let text = try? await store.textAsynchronously(
                for: document
            ), !Task.isCancelled,
              openingDocumentURL == url else {
                if openingDocumentURL == url {
                    openingDocumentURL = nil
                    documentOpenTask = nil
                }
                return
            }
            openingDocumentURL = nil
            documentOpenTask = nil

            libraryMetadata.recordOpened(document.url)

            beginEditing(DocumentSession(document: document, text: text))
        }
    }

    private func render(_ document: Document) {
        perform(.render, with: document)
    }

    private func renderAvailable(_ document: Document) {
        guard libraryIsActive else { return }
        Task {
            guard let text = try? await store.textAsynchronously(for: document) else {
                return
            }

            guard !Task.isCancelled, libraryIsActive,
                  visibleDocuments.contains(where: { $0.url == document.url }) else { return }
            renderingDocumentURL = document.url
            suspendLibraryActivityForDocumentPresentation()
            if settings.renderSoundEnabled {
                RenderSound.shared.play()
            }
            renderingSession = RenderedDocumentSession(
                title: document.displayName,
                markdown: text,
                documentURL: document.url
            )
        }
    }

    private func finishLibraryRendering(from url: URL) {
        guard renderingDocumentURL == url else { return }
        renderingSession = nil
        renderingDocumentURL = nil
        libraryActivityTask = Task {
            await resumeLibraryActivityAfterDocumentPresentation()
        }
    }

    /// Uses the writer's selected New Document flow. Asking for a title remains
    /// the default; the date option skips the naming sheet and uses the same
    /// safe creation path directly.
    private var canCreateUsingCommand: Bool {
        settings.keyboardShortcutsEnabled && store.storageAvailable && libraryIsActive
            && !showingNewDocument && !showingNewFolder && !showingSettings
            && !showingRecentlyDeleted && !showingImporter && !showingPowerPointImportOptions
            && !showingWelcome && !preparingHelpManual && !showingShare && !isImporting
            && countFolder == nil && compilationFolder == nil && renderingSession == nil
            && renamingDocument == nil && renamingFolder == nil && movingItem == nil
            && pendingDeletion == nil && pendingFolderDeletion == nil
    }

    private func newDocument() {
        switch settings.newDocumentCreationMode {
        case .askForTitle:

            showingNewDocument = true
        case .useTodaysDate:

            createDocument(named: NewDocumentTitle.today())
        }
    }

    /// Creates the file with the chosen name and opens it.
    private func createDocument(named name: String) {
        Task {
            guard let url = await store.createDocument(
                named: name,
                contents: "",
                in: currentDirectory
            ) else { return }

            store.refresh()
            guard let document = Document(fileURL: url) else { return }
            libraryMetadata.recordOpened(url)

            beginEditing(DocumentSession(document: document, text: ""))
        }
    }

    private func createFolder(named name: String) {
        _ = store.createFolder(named: name, in: currentDirectory)
    }

    private func open(_ folder: LibraryFolder) {
        searchText = ""
        currentFolderURL = folder.url
    }

    private func navigateBack() {
        guard let currentFolderURL else { return }
        let parent = currentFolderURL.deletingLastPathComponent()
        self.currentFolderURL = parent.standardizedFileURL
            == store.directory.standardizedFileURL ? nil : parent
        searchText = ""
    }

    private func beginRename(_ folder: LibraryFolder) {
        newName = folder.displayName
        renamingFolder = folder
    }

    private func commitFolderRename(_ folder: LibraryFolder) {
        let proposedURL = folder.url.deletingLastPathComponent()
            .appendingPathComponent(DocumentStore.sanitize(newName), isDirectory: true)
        let metadataPairs = store.documentMovePairs(
            fromFolder: folder.url,
            toFolder: proposedURL
        )
        let renamedURL = store.rename(folder, to: newName)
        renamingFolder = nil
        if let renamedURL {
            libraryMetadata.migrateManualOrder(from: folder.url, to: renamedURL)
            migrateFolderMetadata(
                metadataPairs,
                replacingProposedRoot: proposedURL,
                with: renamedURL
            )
        }
    }

    private func beginDelete(_ folder: LibraryFolder) {
        pendingFolderDeletion = folder
    }

    private func cancelFolderDelete() {
        pendingFolderDeletion = nil
    }

    private func commitFolderDelete() {
        guard let folder = pendingFolderDeletion else { return }
        let proposedDeletedURL = store.recentlyDeletedDirectory
            .appendingPathComponent(folder.displayName, isDirectory: true)
        let metadataPairs = store.documentMovePairs(
            fromFolder: folder.url,
            toFolder: proposedDeletedURL
        )
        guard let deletedURL = store.moveToRecentlyDeleted(folder) else {
            pendingFolderDeletion = nil
            return
        }
        libraryMetadata.migrateManualOrder(from: folder.url, to: deletedURL)
        migrateFolderMetadata(
            metadataPairs,
            replacingProposedRoot: proposedDeletedURL,
            with: deletedURL
        )
        pendingFolderDeletion = nil
    }

    private func move(_ item: LibraryItem, to destination: URL) {
        let oldURL = item.url
        let proposedFolderURL = destination.appendingPathComponent(
            item.displayName,
            isDirectory: true
        )
        let folderMetadataPairs: [DocumentMigrationPair]
        if case .folder(let folder) = item {
            folderMetadataPairs = store.documentMovePairs(
                fromFolder: folder.url,
                toFolder: proposedFolderURL
            )
        } else {
            folderMetadataPairs = []
        }
        guard let movedURL = store.move(item, to: destination) else { return }
        switch item {
        case .document:
            EditorPositionStore.shared.migratePosition(from: oldURL, to: movedURL)
            libraryMetadata.migrateMetadata(from: oldURL, to: movedURL)
        case .folder:
            libraryMetadata.migrateManualOrder(from: oldURL, to: movedURL)
            migrateFolderMetadata(
                folderMetadataPairs,
                replacingProposedRoot: proposedFolderURL,
                with: movedURL
            )
        }
    }

    private func beginMove(_ item: LibraryItem) {
        movingItem = item
    }

    private func migrateFolderMetadata(
        _ pairs: [DocumentMigrationPair],
        replacingProposedRoot proposedRoot: URL,
        with actualRoot: URL
    ) {
        for pair in pairs {
            let relativeComponents = pair.destinationURL.pathComponents
                .dropFirst(proposedRoot.pathComponents.count)
            let actualDestination = relativeComponents.reduce(actualRoot) {
                $0.appendingPathComponent($1)
            }
            EditorPositionStore.shared.migratePosition(
                from: pair.sourceURL,
                to: actualDestination
            )
            libraryMetadata.migrateMetadata(
                from: pair.sourceURL,
                to: actualDestination
            )
        }
    }

    private func excludedMoveDestinations(for item: LibraryItem) -> Set<URL> {
        var excluded: Set<URL> = [item.url.deletingLastPathComponent().standardizedFileURL]
        if case .folder(let folder) = item {
            excluded.insert(folder.url.standardizedFileURL)
            for candidate in store.folders where candidate.url.pathComponents.starts(
                with: folder.url.pathComponents
            ) {
                excluded.insert(candidate.url.standardizedFileURL)
            }
        }
        return excluded
    }

    private func beginRename(_ document: Document) {
        newName = document.displayName
        renamingDocument = document
    }

    private func commitRename(_ document: Document) {
        let renamedURL = store.rename(at: document.url, to: newName)
        renamingDocument = nil
        if let renamedURL {
            libraryMetadata.migrateMetadata(
                from: document.url,
                to: renamedURL
            )
        }
    }

    private func duplicate(_ document: Document) {
        perform(.duplicate, with: document)
    }

    private func duplicateAvailable(_ document: Document) {
        Task {
            _ = await store.duplicate(document)
        }
    }

    private func togglePin(_ document: Document) {
        libraryMetadata.togglePin(for: document.url)
    }

    private func share(_ document: Document) {
        perform(.share, with: document)
    }

    private func shareAvailable(_ document: Document) {
        guard let text = try? store.text(for: document) else { return }
        do {
            let url = try ShareItemBuilder.makeFile(
                title: document.displayName,
                markdown: text,
                format: .markdown,
                usesSmartPunctuation: settings.usesSmartPunctuation,
                thematicSeparator: settings.thematicSeparator
            )
            shareItems = [url]

            showingShare = true
        } catch {
            store.lastError = String(localized: "Could not prepare \(document.displayName) for sharing. \(error.localizedDescription)")
        }
    }

    private func cancelDelete() {
        pendingDeletion = nil
    }

    private func beginDelete(_ document: Document) {
        pendingDeletion = document
    }

    private func commitDelete() {
        guard let document = pendingDeletion else { return }
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
    }

    private func finishRenamePresentation() {
        guard let item = pendingRename else { return }
        pendingRename = nil
        switch item {
        case .document(let document): commitRename(document)
        case .folder(let folder): commitFolderRename(folder)
        }
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

    private var folderDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingFolderDeletion != nil },
            set: { if !$0, pendingFolderDeletion != nil { cancelFolderDelete() } }
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

    private var importNoticeBinding: Binding<Bool> {
        Binding(
            get: { importNotice != nil },
            set: { if !$0 { dismissImportNotice() } }
        )
    }

    private var sortFieldBinding: Binding<DocumentSortField> {
        Binding(
            get: { currentSort.field },
            set: { field in
                var updatedSort = currentSort
                updatedSort.field = field
                libraryMetadata.setSort(updatedSort, in: currentDirectory)
            }
        )
    }

    private var sortDirectionBinding: Binding<SortDirection> {
        Binding(
            get: { currentSort.direction },
            set: { direction in
                var updatedSort = currentSort
                updatedSort.direction = direction
                libraryMetadata.setSort(updatedSort, in: currentDirectory)
            }
        )
    }

    private var importContentTypes: [UTType] {
        ["md", "markdown", "mdown", "txt", "docx", "pptx"].compactMap {
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
            guard !isImporting else { return }
            if urls.contains(where: { $0.pathExtension.lowercased() == "pptx" }) {
                pendingImportURLs = urls
                pendingImportDestination = currentDirectory
                pendingImportOptions = nil
                // Retain picker access while the writer chooses import options.
                pendingImportAccess = urls.filter { $0.startAccessingSecurityScopedResource() }
                showingPowerPointImportOptions = true
            } else {
                performImport(urls, into: currentDirectory)
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code != NSUserCancelledError {
                store.lastError = String(localized: "Could not import the selected files. \(error.localizedDescription)")
            }
        }
    }

    private func finishPowerPointImportOptions() {
        let urls = pendingImportURLs
        let destination = pendingImportDestination
        let access = pendingImportAccess
        let options = pendingImportOptions
        pendingImportURLs = []
        pendingImportDestination = nil
        pendingImportAccess = []
        pendingImportOptions = nil
        guard let options else {
            access.forEach { $0.stopAccessingSecurityScopedResource() }

            return
        }
        performImport(urls, into: destination, options: options, scopedAccess: access)
    }

    private func performImport(
        _ urls: [URL],
        into destination: URL?,
        options: PowerPointImportOptions = PowerPointImportOptions(),
        scopedAccess: [URL] = []
    ) {
        isImporting = true
        Task {
            defer {
                scopedAccess.forEach { $0.stopAccessingSecurityScopedResource() }
                isImporting = false
            }
            let importResult = await store.importDocuments(
                from: urls, into: destination, powerPointOptions: options
            )
            if importResult.failedFileNames.isEmpty {
                if !importResult.notices.isEmpty {
                    importNotice = importResult.notices.joined(separator: " ")
                }
            } else {
                // Keep successful-file conversion notices visible in partial batches.
                if !importResult.notices.isEmpty, let failure = store.lastError {
                    store.lastError = failure + " " + importResult.notices.joined(separator: " ")
                }
            }
        }
    }

    private func dismissError() {
        store.lastError = nil
    }

    private func dismissImportNotice() {
        importNotice = nil
    }

    private func configureSelectedStorage() async {
        iCloudMonitor.stop()
        guard libraryIsActive else { return }
        if configuredStorageLocation != storage.selectedLocation {
            currentFolderURL = nil
            configuredStorageLocation = storage.selectedLocation
        }

        let directory = await storage.prepareCurrentLocation()
        guard libraryIsActive else {
            iCloudMonitor.stop()
            return
        }
        libraryMetadata.useLibraryRoot(directory)
        EditorPositionStore.shared.useLibraryRoot(directory)
        guard storage.selectedLocation == .iCloud else {
            downloadTasks.values.forEach { $0.cancel() }
            downloadTasks = [:]
            pendingDocumentActions = [:]
            store.clearICloudSnapshot()
            await store.useDirectoryAsynchronously(
                directory,
                usesICloudStorage: false
            )
            await prepareWelcomeDocumentIfNeeded()
            performAppLaunchBehaviorIfReady()
            return
        }

        await store.useDirectoryAsynchronously(
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

    /// Keep Library updates and announcements paused while a document is open
    /// for editing or rendering, preserving the originating rows.
    private func beginEditing(_ session: DocumentSession) {
        suspendLibraryActivityForDocumentPresentation()
        openedDocument = session
        documentPath = [session.document.url]
    }

    private func suspendLibraryActivityForDocumentPresentation() {
        iCloudMonitor.stop()
        libraryActivityTask?.cancel()
        libraryActivityTask = nil
        store.cancelPendingRefresh()
        searchAnnounceTask?.cancel()
        searchAnnounceTask = nil
    }

    private func resumeLibraryActivityAfterDocumentPresentation() async {
        guard libraryIsActive else { return }
        // Returning through a native link keeps the existing Library and rows.
        // Reconfigure storage only if the storage choice actually changed.
        if configuredStorageLocation != storage.selectedLocation {
            await configureSelectedStorage()
        } else {
            if storage.selectedLocation == .iCloud { iCloudMonitor.start(rootDirectory: store.directory) }
            await store.refreshAsynchronously()
        }
        guard libraryIsActive else { return }
        rebuildLibraryPresentation()
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
        if store.storageAvailable {
            do { _ = try await HelpManualDocument.installIfNeeded(in: store) }
            catch { store.lastError = error.localizedDescription }
        }
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
                return
            }
            open(document)
        case .library, nil:
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

    private func synchronize(_ document: Document) {
        let url = document.url.standardizedFileURL
        guard downloadTasks[url] == nil else { return }

        downloadTasks[url] = Task {
            let succeeded = await store.synchronizeWithICloud(document)
            downloadTasks[url] = nil
            if succeeded {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "\(document.displayName) synced."
                )
            }
        }
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
    let documentURL: URL
}
