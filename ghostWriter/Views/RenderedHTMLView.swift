//
//  RenderedHTMLView.swift
//  ghostWriter
//
//  Presents the rendered markdown as real HTML in a web view. This is
//  deliberately a separate screen rather than a pane beside the editor: it
//  gives the whole display to the rendered document, which matters for anyone
//  reading at a large text size.
//
//  Rendering to HTML rather than to SwiftUI views is the point. A web view
//  exposes genuine headings, lists, links, and tables, so VoiceOver's rotor can
//  navigate the document by heading or by link the way it would any web page.
//

import SwiftUI
import WebKit

struct RenderedHTMLView: View {
    let title: String
    let markdown: String
    var documentURL: URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            HTMLWebView(
                html: html,
                baseURL: documentURL?.deletingLastPathComponent()
            )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Rendered")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { dismiss() }
                    }
                }
        }
    }

    private var html: String {
        HTMLTemplate.document(
            title: title,
            body: MarkdownRenderer.html(
                from: markdown,
                title: title,
                sourceDirectory: documentURL?.deletingLastPathComponent(),
                embedLocalImages: true
            ),
            baseFontPointSize: baseFontPointSize
        )
    }

    private var baseFontPointSize: CGFloat {
        // Reading the SwiftUI value makes the HTML regenerate when Dynamic Type
        // changes while the preview is open. UIFont then supplies the matching
        // platform point size for the web document.
        _ = dynamicTypeSize
        return UIFont.preferredFont(forTextStyle: .body).pointSize
    }
}

struct HTMLWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // No JavaScript is needed to display rendered markdown, and disabling
        // it means a document containing a script tag cannot run it.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(named: "PageBackground") ?? .systemBackground

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html
                || context.coordinator.loadedBaseURL != baseURL else { return }
        context.coordinator.loadedHTML = html
        context.coordinator.loadedBaseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var loadedBaseURL: URL?

        /// Links inside a rendered document open in Safari rather than
        /// navigating away inside the sheet, which would strand the user in a
        /// web browser with no way back to their note.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }
    }
}
