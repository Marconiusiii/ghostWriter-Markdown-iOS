import SwiftUI

struct CompilationExportView: View {
    let directory: URL
    @Environment(DocumentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(DocumentLibraryMetadataStore.self) private var metadata
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CompilationItem] = []
    @State private var expandedFolders: Set<URL> = []
    @FocusState private var focusedField: CompilationTextField?
    @State private var title = "Compilation"
    @State private var options = CompilationExportSettings()
    @State private var themeIsLoading = false
    @State private var editMode = EditMode.inactive
    @State private var initialized = false
    @State private var exporting = false
    @State private var preparedDocumentCount = 0
    @State private var documentTotal = 0
    @State private var creatingWordDocument = false
    @State private var exportStatus = "Preparing documents…"
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
                            .focused($focusedField, equals: .outputName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel("Document name")
                    }
                    Picker("Export format", selection: $options.format) {
                        ForEach(CompilationFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .disabled(exporting)
                CompilationFormatOptions(options: $options, themeIsLoading: $themeIsLoading, focusedField: $focusedField)
                    .disabled(exporting)
                Section("Files and folders") {
                    if editMode.isEditing || items.count > 1 || items.contains(where: \.hasReorderableContents) {
                        FileOrderEditButton(editMode: $editMode)
                    }
                    CompilationRows(
                        items: $items,
                        expandedFolders: $expandedFolders,
                        isEditing: editMode.isEditing
                    )
                }
                .disabled(exporting)
                Section {
                    if exporting {
                        if creatingWordDocument {
                            ProgressView("Creating \(options.format.label) compilation…")
                        } else {
                            ProgressView(value: Double(preparedDocumentCount), total: Double(max(1, documentTotal))) {
                                Text(exportStatus)
                            } currentValueLabel: {
                                Text("\(preparedDocumentCount) of \(documentTotal) documents prepared")
                            }
                            .accessibilityValue("\(preparedDocumentCount) of \(documentTotal) documents prepared")
                        }
                    }
                    Button("Export and share…", action: export)
                        .disabled(includedDocuments.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exporting || themeIsLoading || (options.format == .eBraille && options.eBraille.validationMessage != nil))
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Export Compilation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { exportTask?.cancel(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") { focusedField = nil }
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
                options.powerPointTheme = settings.powerPointTheme
                options.powerPointFont = settings.powerPointFont
                options.eBraille = settings.eBrailleMetadataDefaults
                options.brfGrade = settings.eBrailleGrade
                options.brfCells = settings.brfCellsPerLine
                options.brfLines = settings.brfLinesPerPage
                options.brfCustomLayout = options.brfCells != 40 || options.brfLines != 25
                if directory.standardizedFileURL.path != store.directory.standardizedFileURL.path { title = directory.lastPathComponent }
                items = CompilationSelection.items(
                    in: directory, documents: store.documents,
                    folders: store.folders, metadata: metadata
                )
                expandedFolders = []
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
        focusedField = nil
        exporting = true
        editMode = .inactive
        let selected = includedDocuments
        preparedDocumentCount = 0
        documentTotal = selected.count
        creatingWordDocument = false
        exportStatus = "Preparing documents…"
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
                        exportStatus = "Downloading \(document.displayName)…"
                        guard await store.requestDownload(for: current) else {
                            throw WordThemeError.invalid("Could not download \(current.displayName). Try again when it is available in the Library.")
                        }
                    }
                    let available = store.documents.first { $0.url == document.url } ?? current
                    exportStatus = "Reading \(document.displayName)…"
                    let markdown: String
                    do { markdown = try await store.textAsynchronously(for: available, reportFailure: false) }
                    catch { throw WordThemeError.invalid("Could not read \(document.displayName). \(error.localizedDescription)") }
                    sources.append(WordCompilationSource(title: document.displayName, markdown: markdown, sourceDirectory: document.url.deletingLastPathComponent(), language: DocumentLanguage.resolvedTag(metadata.documentLanguage(for: document.url)), sourceURL: document.url))
                    preparedDocumentCount += 1
                }
                try Task.checkCancellation()
                creatingWordDocument = true
                let inputs = sources
                let work = Task.detached(priority: .userInitiated) { () throws -> URL in
                    try await CompilationFileWriter.write(title: outputTitle, sources: inputs, settings: exportOptions)
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
                    Toggle("\(entry.item.displayName) Folder", isOn: $entry.isIncluded)
                        .accessibilityHint(entry.isIncluded ? "Double-tap to exclude" : "Double-tap to include")
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
                    Text(entry.item.displayName)
                }
                .moveDisabled(!isEditing || items.count < 2)
            } else if isEditing {
                Text(entry.item.displayName)
                    .moveDisabled(items.count < 2)
            } else {
                Toggle(entry.item.displayName, isOn: $entry.isIncluded)
                    .accessibilityHint(entry.isIncluded ? "Double-tap to exclude" : "Double-tap to include")
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
