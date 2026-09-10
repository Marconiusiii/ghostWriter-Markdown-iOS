import SwiftUI
import UniformTypeIdentifiers

struct WordThemeImportSection: View {
    @Binding var theme: WordExportTheme?
    @State private var themeName: String?
    @State private var showingImporter = false
    @State private var errorMessage: String?
    @Binding var isLoading: Bool

    var body: some View {
        Section("JSON style sheet") {
            Text(themeName ?? "Standard Word appearance")
            Button("Import JSON style sheet…") { showingImporter = true }
                .disabled(isLoading)
            if theme != nil {
                Button("Remove style sheet") { theme = nil; themeName = nil }
            }
            if isLoading { ProgressView("Reading style sheet…") }
            NavigationLink("Word Export Help") { WordExportHelpView() }
            Text("Optional. Supplied settings override the standard Word appearance. Word Export Help describes the format and includes an example.")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                isLoading = true
                Task {
                    let loaded = await Task.detached { () -> Result<WordExportTheme, Error> in
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return Result { try WordExportTheme.load(from: url) }
                    }.value
                    isLoading = false
                    switch loaded {
                    case .success(let value): theme = value; themeName = url.lastPathComponent
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Style sheet could not be imported", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

struct WordExportOptionsView: View {
    let onCancel: () -> Void
    let onExport: (WordExportOptions) -> Void
    @State private var options = WordExportOptions()
    @State private var themeIsLoading = false

    var body: some View {
        NavigationStack {
            Form {
                WordThemeImportSection(theme: $options.theme, isLoading: $themeIsLoading)
                Section { Button("Export and share…") { onExport(options) }.disabled(themeIsLoading) }
            }
            .navigationTitle("Word export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
        }
    }
}
