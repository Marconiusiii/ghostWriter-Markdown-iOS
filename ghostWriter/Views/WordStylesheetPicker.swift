import SwiftUI

struct WordStylesheetPicker: View {
    @Binding var selection: String
    @Environment(DocumentStore.self) private var store
    @State private var choices: [WordStylesheetLoader.Choice] = []
    @State private var loading = true
    @State private var failure: String?

    var body: some View {
        Section("Word stylesheet") {
            Picker("Stylesheet", selection: $selection) {
                Text("Standard Word output").tag("")
                ForEach(choices.filter { $0.error == nil }) { choice in
                    Text(choice.name).tag(choice.filename)
                }
                if !selection.isEmpty, !choices.contains(where: { $0.filename == selection && $0.error == nil }) {
                    Text("\(selection) — unavailable").tag(selection)
                }
            }
            .pickerStyle(.wheel)
            if loading { ProgressView("Checking stylesheets…") }
            if let failure { Text(failure) }
            ForEach(choices.filter { $0.error != nil }) { choice in
                Text("\(choice.filename): \(choice.error ?? "")")
            }
            Text("Add JSON files to Word Stylesheets in your library. Standard Word output uses no custom stylesheet.")
        }
        .task {
            do {
                let root = store.directory
                let work = Task.detached { try await WordStylesheetLoader.choices(in: root) }
                choices = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            } catch is CancellationError { return }
            catch { failure = error.localizedDescription }
            loading = false
        }
    }

}
