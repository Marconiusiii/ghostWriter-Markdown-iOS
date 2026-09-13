import SwiftUI

struct DocumentCountView: View {
    let document: Document
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var result: FolderTextCount?
    @State private var failure: String?
    @State private var status = "Preparing count…"

    private var finished: Bool { result != nil || failure != nil }

    var body: some View {
        NavigationStack {
            List {
                Section { Text(document.displayName) }
                if let result {
                    Section {
                        LabeledContent("Words", value: result.words.formatted())
                        LabeledContent("Sentences", value: result.sentences.formatted())
                        LabeledContent("Characters", value: result.characters.formatted())
                    }
                } else if let failure {
                    Section("Unable to count document") { Text(failure) }
                } else {
                    ProgressView(status)
                }
            }
            .navigationTitle("Word Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Done" : "Cancel") { dismiss() }
                }
            }
            .task(id: document.url) { await count() }
        }
    }

    private func count() async {
        guard !finished else { return }
        do {
            var current = store.documents.first { $0.url == document.url } ?? document
            if !current.availability.isAvailable {
                status = "Downloading document…"
                guard await store.requestDownload(for: current) else {
                    throw WordThemeError.invalid("This document could not be downloaded. Try again when it is available.")
                }
                current = store.documents.first { $0.url == document.url } ?? current
            }
            try Task.checkCancellation()
            status = "Counting document…"
            let text = try await store.textAsynchronously(for: current, reportFailure: false)
            try Task.checkCancellation()
            let work = Task.detached(priority: .userInitiated) {
                try FolderTextCount.count(text)
            }
            let count = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            try Task.checkCancellation()
            result = count
        } catch is CancellationError { }
        catch { failure = error.localizedDescription }
    }
}
