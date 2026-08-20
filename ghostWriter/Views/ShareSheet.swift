//
//  ShareSheet.swift
//  ghostWriter
//
//  Wraps UIActivityViewController. The system share sheet is fully accessible
//  already, so this is a thin bridge rather than anything custom.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LinkPresentation

/// Supplies the system share sheet with a complete filename for its preview
/// while continuing to hand the selected activity the original file URL.
final class ShareFileActivityItemSource: NSObject, UIActivityItemSource {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        fileURL
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = fileURL
        metadata.url = fileURL
        metadata.title = fileURL.lastPathComponent
        return metadata
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType(filenameExtension: fileURL.pathExtension)?.identifier
            ?? UTType.data.identifier
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityItems = items.map { item -> Any in
            guard let url = item as? URL, url.isFileURL else { return item }
            return ShareFileActivityItemSource(fileURL: url)
        }
        return UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The editor's Share destination.
///
/// `ShareLink` presents the system sheet itself and reports nothing back when
/// it closes, so there is no point at which the app can restore VoiceOver
/// focus — it fell to the first element on screen, the Back button. The system
/// sheet also offers no Close button, leaving the two-finger scrub as the only
/// way out. Presenting the activity controller inside a sheet the app owns
/// fixes both: Close is an ordinary button, and dismissal is observable.
struct EditorShareView: View {
    let format: EditorView.EditorShareFormat
    let title: String
    let fileName: String
    let markdown: String
    let sourceDirectory: URL?
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings

    @State private var fileURL: URL?
    @State private var failureMessage: String?

    /// Set once the writer has confirmed the export options. Formats that need
    /// none begin preparing immediately; the braille formats wait here, which
    /// is why preparation is keyed on these rather than started in `task`.
    ///
    /// The two braille formats ask for different things: eBraille carries
    /// metadata a BRF file has nowhere to put, and BRF needs a page geometry
    /// eBraille leaves to the reading system.
    @State private var eBrailleMetadata: EBrailleMetadata?
    @State private var brfOptions: BRFExportOptions?

    var body: some View {
        Group {
            if let failureMessage {
                // Only this state needs a Close button of its own. There is no
                // activity controller here to supply one, and without it the
                // sheet would be a dead end.
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(failureMessage)
                            .font(.body)
                            .foregroundStyle(Color.ghostText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .navigationTitle("Share Failed")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", action: onClose)
                        }
                    }
                }
            } else if format == .eBraille, eBrailleMetadata == nil {
                EBrailleOptionsView(
                    settings: settings,
                    documentTitle: title,
                    onCancel: onClose,
                    onExport: { metadata in
                        eBrailleMetadata = metadata
                    }
                )
            } else if format == .brf, brfOptions == nil {
                BRFOptionsView(
                    settings: settings,
                    onCancel: onClose,
                    onExport: { options in
                        brfOptions = options
                    }
                )
            } else if let fileURL {
                // UIActivityViewController supplies its own Close button, in
                // the right place — after the document name and before the
                // sharing destinations. Wrapping this in a navigation stack
                // would add a second one.
                ShareSheet(items: [fileURL])
            } else {
                ProgressView("Preparing \(format.label)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await prepareFile()
        }
        .task(id: eBrailleMetadata) {
            await prepareFile()
        }
        .task(id: brfOptions) {
            await prepareFile()
        }
    }

    /// Conversion and file writing happen off the main thread. A large Word
    /// export is real work, and doing it inline would freeze the sheet as it
    /// appeared.
    private func prepareFile() async {
        guard fileURL == nil, failureMessage == nil else { return }
        // Neither braille format can be written until its options are in.
        if format == .eBraille, eBrailleMetadata == nil { return }
        if format == .brf, brfOptions == nil { return }

        let format = format
        let title = title
        let fileName = fileName
        let markdown = markdown
        let sourceDirectory = sourceDirectory
        let metadata = eBrailleMetadata
        let brf = brfOptions

        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
            do {
                return .success(
                    try await EditorShareFileWriter.write(
                        format: format,
                        title: title,
                        fileName: fileName,
                        markdown: markdown,
                        sourceDirectory: sourceDirectory,
                        eBrailleMetadata: metadata,
                        brfOptions: brf
                    )
                )
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let url):
            fileURL = url
        case .failure(let error):
            failureMessage = "\(title) could not be prepared for sharing. \(error.localizedDescription)"
        }
    }
}

/// Writes the shared document to a uniquely named temporary directory, so two
/// shares of the same document cannot overwrite one another mid-transfer.
nonisolated enum EditorShareFileWriter {
    static func write(
        format: EditorView.EditorShareFormat,
        title: String,
        fileName: String,
        markdown: String,
        sourceDirectory: URL?,
        eBrailleMetadata: EBrailleMetadata? = nil,
        brfOptions: BRFExportOptions? = nil
    ) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ghostWriter-Share-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let safeName = fileName.isEmpty ? "Document" : fileName

        switch format {
        case .markdown:
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("md")
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        case .plainText:
            // Not the markdown source. This option used to hand over the raw
            // text, which meant the recipient got hashes and asterisks read
            // aloud as punctuation — the least readable of the formats, under
            // the name that promised the most readable.
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("txt")
            let contents = PlainTextWriter.write(title: title, markdown: markdown)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        case .html:
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("html")
            let contents = ShareItemBuilder.contents(
                title: title,
                markdown: markdown,
                format: .html
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        case .word:
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("docx")
            let data = try MarkdownToWordConverter.convert(
                title: title,
                markdown: markdown,
                sourceDirectory: sourceDirectory
            )
            try data.write(to: url, options: .atomic)
            return url
        case .pdf:
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("pdf")
            let data = try TaggedPDFWriter.write(
                title: title,
                markdown: markdown,
                sourceDirectory: sourceDirectory
            )
            try data.write(to: url, options: .atomic)
            return url
        case .epub:
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("epub")
            let data = try EPUBWriter.write(
                title: title,
                markdown: markdown,
                sourceDirectory: sourceDirectory
            )
            try data.write(to: url, options: .atomic)
            return url
        case .eBraille:
            // .ebrl is the packaged eBraille extension. The metadata is
            // required, so its absence is a programming error rather than
            // something to paper over with defaults.
            guard let eBrailleMetadata else {
                throw BrailleTranslationError.tablesMissing
            }
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("ebrl")
            let data = try await EBrailleWriter.write(
                title: title,
                markdown: markdown,
                metadata: eBrailleMetadata,
                translator: LiblouisBridge.shared,
                sourceDirectory: sourceDirectory
            )
            try data.write(to: url, options: .atomic)
            return url
        case .brf:
            // The page geometry is written into the file, so it has to be
            // chosen before the file exists.
            guard let brfOptions else {
                throw BrailleTranslationError.tablesMissing
            }
            let url = directory.appendingPathComponent(safeName)
                .appendingPathExtension("brf")
            let data = try await BRFWriter.write(
                markdown: markdown,
                title: title,
                grade: brfOptions.grade,
                pageSetup: brfOptions.pageSetup,
                translator: LiblouisBridge.shared
            )
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}

/// Builds the temporary files offered when sharing a document. Writing real
/// files rather than sharing raw strings means the receiving app gets a
/// properly named document with the right type.
enum ShareItemBuilder {

    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case plainText
        case html

        var id: String { rawValue }

        var label: String {
            switch self {
            case .markdown: return "Markdown"
            case .plainText: return "Plain Text"
            case .html: return "HTML"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .plainText: return "txt"
            case .html: return "html"
            }
        }
    }

    /// Writes the document in the requested format to a temporary file. Errors
    /// are thrown so the presenting view can explain what failed rather than
    /// making the Share action appear unresponsive.
    static func makeFile(title: String, markdown: String, format: Format) throws -> URL {
        let contents = contents(title: title, markdown: markdown, format: format)

        let safeName = DocumentStore.sanitize(title)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension(format.fileExtension)

        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Produces the exact bytes represented by each share format. Keeping this
    /// separate from presentation lets ShareLink generate its file only when the
    /// system actually begins a transfer.
    static func contents(title: String, markdown: String, format: Format) -> String {
        switch format {
        case .markdown:
            return markdown
        case .plainText:
            return PlainTextWriter.write(title: title, markdown: markdown)
        case .html:
            return HTMLTemplate.exportDocument(
                title: title,
                body: MarkdownRenderer.html(from: markdown)
            )
        }
    }
}

/// ShareLink uses these concrete types so the system receives the real content
/// type instead of having to infer it from an untyped `[Any]` activity item.
nonisolated struct MarkdownShareFile: Transferable {
    let fileName: String
    let contents: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: markdownType) { item in
            SentTransferredFile(
                try writeShareFile(
                    named: item.fileName,
                    fileExtension: "md",
                    contents: item.contents
                )
            )
        }
    }

    private static let markdownType =
        UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
}

nonisolated struct PlainTextShareFile: Transferable {
    let fileName: String
    let contents: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            SentTransferredFile(
                try writeShareFile(
                    named: item.fileName,
                    fileExtension: "txt",
                    contents: item.contents
                )
            )
        }
    }
}

nonisolated struct HTMLShareFile: Transferable {
    let fileName: String
    let contents: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .html) { item in
            SentTransferredFile(
                try writeShareFile(
                    named: item.fileName,
                    fileExtension: "html",
                    contents: item.contents
                )
            )
        }
    }
}

nonisolated struct WordShareFile: Transferable {
    let fileName: String
    let title: String
    let markdown: String
    var sourceDirectory: URL? = nil

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: wordType) { item in
            let data = try MarkdownToWordConverter.convert(
                title: item.title,
                markdown: item.markdown,
                sourceDirectory: item.sourceDirectory
            )
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "ghostWriter-Word-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory
                .appendingPathComponent(item.fileName)
                .appendingPathExtension("docx")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    private static let wordType = UTType(
        filenameExtension: "docx",
        conformingTo: .data
    ) ?? .data
}

nonisolated private func writeShareFile(
    named fileName: String,
    fileExtension: String,
    contents: String
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(fileName)
        .appendingPathExtension(fileExtension)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}
