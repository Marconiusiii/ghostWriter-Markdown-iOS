import SwiftUI

struct CompilationExportView: View {
    let directory: URL
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var metadata
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [Document] = []
    @State private var title = "Compilation"
    @State private var options = WordExportOptions()
    @State private var themeIsLoading = false
    @State private var editMode = EditMode.inactive
    @State private var selecting = false
    @State private var initialized = false
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var sharedFile: CompilationSharedFile?

    var body: some View {
        NavigationStack {
            List {
                Section("Output") {
                    TextField("Document name", text: $title)
                    Toggle("Start each document on a new page", isOn: $options.startsDocumentsOnNewPages)
                    Toggle("Preserve individual document heading structure", isOn: $options.preservesHeadingStructure)
                    if !options.preservesHeadingStructure {
                        Text("The first document’s title is the only Heading 1. All other headings move down one level.")
                        Text(WordCompilation.headingWarning)
                    }
                }
                Section("Documents in export order") {
                    Text("\(documents.count) documents")
                    Button("Add documents or folders…") { selecting = true }
                    if documents.count > 1 { EditButton() }
                    ForEach(documents) { document in
                        VStack(alignment: .leading) {
                            Text(document.displayName)
                            Text(relativePath(document.url)).font(.caption)
                        }
                        .contextMenu {
                            Button("Remove from compilation", role: .destructive) {
                                documents.removeAll { $0.id == document.id }
                            }
                        }
                    }
                    .onMove { documents.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { documents.remove(atOffsets: $0) }
                    Text("Pinning does not change this order. Removing a document here leaves its Library file unchanged.")
                }
                WordThemeImportSection(theme: $options.theme, isLoading: $themeIsLoading)
                Section {
                    if exporting { ProgressView("Preparing compilation…") }
                    Button("Export and share…", action: export)
                        .disabled(documents.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exporting || themeIsLoading)
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
            }
            .sheet(isPresented: $selecting) {
                CompilationPickerView(directory: directory) { added in
                    documents = CompilationSelection.appending(added, to: documents)
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
                documents = CompilationSelection.documents(in: directory, documents: store.documents, folders: store.folders, metadata: metadata)
            }
            .onDisappear { exportTask?.cancel() }
        }
        .interactiveDismissDisabled(exporting)
    }

    private func relativePath(_ url: URL) -> String {
        url.pathComponents.dropFirst(store.directory.pathComponents.count).joined(separator: "/")
    }

    private func export() {
        guard !exporting else { return }
        exporting = true
        editMode = .inactive
        let selected = documents
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

/// Checkboxes are ordinary native toggles. Folder selection expands recursively on Add.
private struct CompilationPickerView: View {
    let directory: URL
    let onAdd: ([Document]) -> Void
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var metadata
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<URL> = []
    @State private var currentDirectory: URL?

    private var location: URL { currentDirectory ?? directory }
    private var items: [LibraryItem] {
        let values = store.folders.filter { $0.url.deletingLastPathComponent().standardizedFileURL.path == location.standardizedFileURL.path }.map(LibraryItem.folder)
            + store.documents.filter { $0.url.deletingLastPathComponent().standardizedFileURL.path == location.standardizedFileURL.path }.map(LibraryItem.document)
        let byURL = Dictionary(uniqueKeysWithValues: values.map { ($0.url, $0) })
        return metadata.manuallyOrdered(values.map(\.url)).compactMap { byURL[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                Text(location.standardizedFileURL.path == store.directory.standardizedFileURL.path ? "Documents" : location.lastPathComponent)
                if location.standardizedFileURL.path != store.directory.standardizedFileURL.path {
                    Button("Go to parent folder") { currentDirectory = location.deletingLastPathComponent() }
                }
                ForEach(items) { item in
                    Toggle(item.isFolder ? "Include folder: \(item.displayName)" : "Include document: \(item.displayName)", isOn: Binding(
                        get: { selected.contains(item.url) },
                        set: { if $0 { selected.insert(item.url) } else { selected.remove(item.url) } }
                    ))
                    if item.isFolder { Button("Open folder: \(item.displayName)") { currentDirectory = item.url } }
                }
            }
            .navigationTitle("Add documents or folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let all = CompilationSelection.documents(in: store.directory, documents: store.documents, folders: store.folders, metadata: metadata)
                        let included = all.filter { document in
                            selected.contains(document.url) || selected.contains { url in document.url.pathComponents.starts(with: url.pathComponents) }
                        }
                        onAdd(included)
                        dismiss()
                    }.disabled(selected.isEmpty)
                }
            }
        }
    }
}
