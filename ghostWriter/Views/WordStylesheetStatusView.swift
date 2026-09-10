import SwiftUI

/// Source information appears only while automatic stylesheet use is enabled.
struct WordStylesheetStatusView: View {
    @Environment(DocumentStorage.self) private var storage
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0
    @State private var status: Status = .loading
    private enum Status { case loading, standard, ready, failed(String) }
    private struct Request: Equatable { let root: URL?; let refresh: Int }

    var body: some View {
        LabeledContent("Location", value: "\(storage.selectedLocation.label) / ghostWriter / Word Stylesheets")
        .task(id: Request(root: storage.activeDirectory, refresh: refresh)) {
            status = .loading
            guard let root = storage.activeDirectory else {
                status = .failed(storage.statusDescription)
                return
            }
            let work = Task.detached(priority: .userInitiated) {
                try await WordStylesheetLoader.load(in: root, enabled: true)
            }
            do {
                let theme = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                status = theme == nil ? .standard : .ready
            } catch is CancellationError { }
            catch { status = .failed("Word Stylesheet could not be read. \(error.localizedDescription)") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh += 1 }
        }
        switch status {
        case .loading: ProgressView("Checking Word Stylesheet…")
        case .standard: Text("Using standard Word styles. No stylesheet found.")
        case .ready: LabeledContent("Stylesheet", value: WordStylesheetLoader.filename)
        case .failed(let message):
            LabeledContent("Stylesheet", value: WordStylesheetLoader.filename)
            Text(message)
        }
    }
}
