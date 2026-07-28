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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
        case .markdown, .plainText:
            return markdown
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
