import SwiftUI

struct CompilationExportView: View {
    let directory: URL
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var metadata
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CompilationItem] = []
    @State private var expandedFolders: Set<URL> = []
    @FocusState private var nameFieldFocused: Bool
    @State private var title = "Compilation"
    @State private var options = WordExportOptions()
    @State private var themeIsLoading = false
    @State private var editMode = EditMode.inactive
    @State private var initialized = false
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var sharedFile: CompilationSharedFile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Document name")
                            .font(.subheadline)
                            .accessibilityHidden(true)
                        TextField("", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel("Document name")
                    }
                    Toggle("Start each document on a new page", isOn: $options.startsDocumentsOnNewPages)
                    Toggle("Preserve individual document heading structure", isOn: $options.preservesHeadingStructure)
                    if !options.preservesHeadingStructure {
                        Text("The first document’s title is the only Heading 1. All other headings move down one level.")
                        Text(WordCompilation.headingWarning)
                    }
                }
                Section("Files and folders") {
                    if editMode.isEditing || items.contains(where: \.hasReorderableContents) {
                        FileOrderEditButton(editMode: $editMode)
                    }
                    CompilationRows(
                        items: $items,
                        expandedFolders: $expandedFolders,
                        isEditing: editMode.isEditing
                    )
                }
                WordThemeImportSection(theme: $options.theme, isLoading: $themeIsLoading)
                Section {
                    if exporting { ProgressView("Preparing compilation…") }
                    Button("Export and share…", action: export)
                        .disabled(includedDocuments.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exporting || themeIsLoading)
                }
            }
            .environment(\.editMode, $editMode)
            .disabled(exporting)
            .navigationTitle("Export Compilation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { exportTask?.cancel(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") { nameFieldFocused = false }
                        .accessibilityLabel("Dismiss keyboard")
                }
            }
            .sheet(item: $sharedFile) { file in ShareSheet(items: [file.url]) }
            .alert("Compilation could not be exported", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if directory.standardizedFileURL.path != store.directory.standardizedFileURL.path { title = directory.lastPathComponent }
                let root = CompilationSelection.folder(
                    at: directory, documents: store.documents,
                    folders: store.folders, metadata: metadata
                )
                items = [root]
                expandedFolders = [root.id]
            }
            .onDisappear { exportTask?.cancel() }
        }
        .interactiveDismissDisabled(exporting)
    }

    private var includedDocuments: [Document] {
        items.flatMap(\.includedDocuments)
    }

    private func export() {
        guard !exporting else { return }
        nameFieldFocused = false
        exporting = true
        editMode = .inactive
        let selected = includedDocuments
        let outputTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let exportOptions = options
        exportTask = Task {
            defer { exporting = false }
            do {
                var sources: [WordCompilationSource] = []
                for document in selected {
                    try Task.checkCancellation()
                    let current = store.documents.first { $0.url == document.url } ?? document
                    if !current.availability.isAvailable {
                        guard await store.requestDownload(for: current) else {
                            throw WordThemeError.invalid("Could not download \(current.displayName). Try again when it is available in the Library.")
                        }
                    }
                    let available = store.documents.first { $0.url == document.url } ?? current
                    let markdown: String
                    do { markdown = try await store.textAsynchronously(for: available, reportFailure: false) }
                    catch { throw WordThemeError.invalid("Could not read \(document.displayName). \(error.localizedDescription)") }
                    sources.append(WordCompilationSource(title: document.displayName, markdown: markdown, sourceDirectory: document.url.deletingLastPathComponent(), language: DocumentLanguage.resolvedTag(metadata.documentLanguage(for: document.url))))
                }
                let inputs = sources
                let work = Task.detached(priority: .userInitiated) { () throws -> URL in
                    try Task.checkCancellation()
                    let data = try WordCompilation.write(title: outputTitle, sources: inputs, options: exportOptions)
                    try Task.checkCancellation()
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ghostWriter-Compilation-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let safeName = outputTitle.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-")
                    let url = directory.appendingPathComponent(String(safeName.prefix(120))).appendingPathExtension("docx")
                    do { try data.write(to: url, options: .atomic) }
                    catch { try? FileManager.default.removeItem(at: directory); throw error }
                    return url
                }
                let url = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                if Task.isCancelled { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); return }
                sharedFile = CompilationSharedFile(url: url)
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct CompilationSharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Selection uses native Toggles and DisclosureGroups. Edit mode removes the
/// Toggles, leaving exactly one movable row per item at each folder level.
private struct CompilationRows: View {
    @Binding var items: [CompilationItem]
    @Binding var expandedFolders: Set<URL>
    let isEditing: Bool
    var parentIncluded = true

    var body: some View {
        ForEach($items) { $entry in
            if entry.item.isFolder {
                if !isEditing {
                    Toggle("Include \(entry.item.displayName)", isOn: $entry.isIncluded)
                        .disabled(!parentIncluded)
                }
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedFolders.contains(entry.id) },
                    set: { expanded in
                        if expanded { expandedFolders.insert(entry.id) }
                        else { expandedFolders.remove(entry.id) }
                    }
                )) {
                    AnyView(CompilationRows(
                        items: $entry.children,
                        expandedFolders: $expandedFolders,
                        isEditing: isEditing,
                        parentIncluded: parentIncluded && entry.isIncluded
                    ))
                } label: {
                    Text(isEditing ? entry.item.displayName : "Contents")
                }
                .moveDisabled(!isEditing || items.count < 2)
            } else if isEditing {
                Text(entry.item.displayName)
                    .moveDisabled(items.count < 2)
            } else {
                Toggle(entry.item.displayName, isOn: $entry.isIncluded)
                    .disabled(!parentIncluded)
            }
        }
        .onMove { offsets, destination in
            guard isEditing else { return }
            move(from: offsets, to: destination)
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
    }
}
