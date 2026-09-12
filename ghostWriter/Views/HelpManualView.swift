import SwiftUI

/// The bundle is the stable identity; user copies are ordinary library files.
enum HelpManualDocument {
    static var url: URL? {
        Bundle.main.url(forResource: "ghostWriter Help", withExtension: "md", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "ghostWriter Help", withExtension: "md")
    }

    static func isBundled(_ candidate: URL?) -> Bool {
        guard let candidate, let url else { return false }
        return candidate.standardizedFileURL == url.standardizedFileURL
    }
}

struct HelpManualView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var document: Document?
    @State private var text = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    EditorView(document: document, initialText: text)
                } else if let failure {
                    Text(failure)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                } else {
                    ProgressView("Opening Help Manual…")
                }
            }
            .task {
                guard document == nil else { return }
                do {
                    guard let url = HelpManualDocument.url, let loaded = Document(fileURL: url) else {
                        throw WordThemeError.invalid("The bundled Help Manual could not be found.")
                    }
                    text = try String(contentsOf: url, encoding: .utf8)
                    document = loaded
                } catch { failure = error.localizedDescription }
            }
        }
    }
}
