import SwiftUI

struct FolderCountView: View {
    let folder: LibraryFolder
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var metadata
    @Environment(\.dismiss) private var dismiss
    @State private var words = 0
    @State private var characters = 0
    @State private var sentences = 0
    @State private var counted = 0
    @State private var processed = 0
    @State private var total = 0
    @State private var finished = false
    @State private var failures: [String] = []
    @State private var status = "Preparing count…"

    var body: some View {
        NavigationStack {
            List {
                Section { Text(folder.displayName) }
                if finished {
                    Section {
                        LabeledContent("Words", value: words.formatted())
                        LabeledContent("Sentences", value: sentences.formatted())
                        LabeledContent("Characters", value: characters.formatted())
                        LabeledContent("Documents counted", value: "\(counted.formatted()) of \(total.formatted())")
                        Text("Counts Markdown source, including syntax, spaces, and line breaks. Files and folders excluded from compilations are also excluded from these totals. Sentence counts use automatic language analysis of the Markdown source.")
                    } header: {
                        if !failures.isEmpty { Text("Partial total") }
                    }
                } else {
                    ProgressView(value: Double(processed), total: Double(max(1, total))) {
                        Text(status)
                    } currentValueLabel: {
                        Text("\(processed) of \(total) documents processed")
                    }
                }
                if !failures.isEmpty {
                    Section("Files not counted") {
                        ForEach(failures, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Total Word Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Done" : "Cancel") { dismiss() }
                }
            }
            .task { await count() }
        }
    }

    private func count() async {
        let root = folder.url.standardizedFileURL.path + "/"
        let documents = store.documents.filter { $0.url.standardizedFileURL.path.hasPrefix(root) }
        total = documents.count
        let included = Set(documents.filter { metadata.isIncludedInStatistics($0.url) }.map(\.url))
        for document in documents {
            if Task.isCancelled { return }
            guard included.contains(document.url) else { processed += 1; continue }
            status = "Reading \(document.displayName)…"
            do {
                let current = store.documents.first { $0.url == document.url } ?? document
                if !current.availability.isAvailable {
                    status = "Downloading \(document.displayName)…"
                    guard await store.requestDownload(for: current) else {
                        throw WordThemeError.invalid("Not available to download.")
                    }
                }
                try Task.checkCancellation()
                let text = try await store.textAsynchronously(for: current, reportFailure: false)
                let work = Task.detached(priority: .userInitiated) {
                    try FolderTextCount.count(text)
                }
                let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                words += result.words
                characters += result.characters
                sentences += result.sentences
                counted += 1
            } catch is CancellationError { return }
            catch { failures.append("\(document.url.path.replacingOccurrences(of: root, with: "")): \(error.localizedDescription)") }
            processed += 1
        }
        finished = true
    }
}
