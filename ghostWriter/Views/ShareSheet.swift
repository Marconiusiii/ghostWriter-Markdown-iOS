//
//  ShareSheet.swift
//  ghostWriter
//
//  Wraps UIActivityViewController. The system share sheet is fully accessible
//  already, so this is a thin bridge rather than anything custom.
//

import SwiftUI
import UIKit

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

    /// Writes the document in the requested format to a temporary file and
    /// returns its URL, or nil if writing failed.
    static func makeFile(title: String, markdown: String, format: Format) -> URL? {
        let contents: String
        switch format {
        case .markdown, .plainText:
            contents = markdown
        case .html:
            contents = HTMLTemplate.exportDocument(
                title: title,
                body: MarkdownRenderer.html(from: markdown)
            )
        }

        let safeName = DocumentStore.sanitize(title)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension(format.fileExtension)

        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
