import SwiftUI

/// One destination for row links, new documents, launch shortcuts, and Help.
struct LibraryEditorDestination: View {
    let url: URL
    let prepareForClose: (URL) async -> Void
    var preparedSession: DocumentSession?
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var metadata
    @State private var session: DocumentSession?
    @State private var failure: String?

    init(url: URL, preparedSession: DocumentSession? = nil,
         prepareForClose: @escaping (URL) async -> Void = { _ in }) {
        self.prepareForClose = prepareForClose
        self.url = url
        self.preparedSession = preparedSession
        _session = State(initialValue: preparedSession?.document.url == url ? preparedSession : nil)
    }

    var body: some View {
        Group {
            if let session {
                EditorView(document: session.document, initialText: session.text,
                           prepareForClose: prepareForClose)
            } else {
                Group {
                    if let failure {
                        Text(failure).padding()
                    } else {
                        ProgressView("Opening document…")
                    }
                }
                .navigationTitle(url.deletingPathExtension().lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
            }
        }
        .task(id: url) {
            guard session == nil else { return }
            if let preparedSession, preparedSession.document.url == url {
                session = preparedSession
                return
            }
            do {
                guard var document = store.documents.first(where: { $0.url == url }) ?? Document(fileURL: url) else {
                    throw WordThemeError.invalid("This document is no longer available in the Library.")
                }
                if !document.availability.isAvailable {
                    guard await store.requestDownload(for: document) else {
                        throw WordThemeError.invalid("This document could not be downloaded. Return to the Library and try again.")
                    }
                    document = store.documents.first(where: { $0.url == url }) ?? document
                }
                let text = try await store.textAsynchronously(for: document, reportFailure: false)
                try Task.checkCancellation()
                metadata.recordOpened(url)
                session = DocumentSession(document: document, text: text)
            } catch is CancellationError { }
            catch { failure = error.localizedDescription }
        }
    }
}
