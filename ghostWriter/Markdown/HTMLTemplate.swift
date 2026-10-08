//
//  HTMLTemplate.swift
//  ghostWriter
//
//  Wraps rendered markdown in a complete HTML document. The CSS is the web
//  app's ghostStyle.css translated so that every size is expressed relative to
//  the reader's Dynamic Type setting rather than in fixed pixels, and so light
//  and dark follow the system.
//

import Foundation

nonisolated enum HTMLTemplate {

    /// A full document for display in the in-app web view.
    ///
    /// - Parameters:
    ///   - title: Used only as the HTML document title.
    ///   - body: Rendered HTML fragment.
    ///   - baseFontPointSize: The reader's current body text size, taken from
    ///     the trait environment so the web view matches the rest of the app.
    static func document(
        title: String,
        language: String = DocumentLanguage.resolvedTag(""),
        body: String,
        baseFontPointSize: CGFloat
    ) -> String {
        let content = body.isEmpty
            ? "<p class=\"empty-state\">This document is empty.</p>"
            : body

        return """
        <!DOCTYPE html>
        <html lang="\(MarkdownRenderer.escape(language))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(MarkdownRenderer.escape(title))</title>
        <style>
        \(stylesheet(baseFontPointSize: baseFontPointSize))
        </style>
        </head>
        <body>
        <main>
        \(content)
        </main>
        </body>
        </html>
        """
    }

    /// A standalone document for export or sharing. Font sizing is left to the
    /// receiving application rather than pinned to this device's settings.
    static func exportDocument(
        title: String,
        language: String = DocumentLanguage.resolvedTag(""),
        style: HTMLExportStyle = .standard,
        body: String
    ) -> String {
        let exportBody = style == .ghostWriter
            ? body.replacingOccurrences(of: "<div class=\"table-scroll\">", with: "<div class=\"table-scroll\" tabindex=\"0\">")
            : body
        let content = body.isEmpty
            ? "<p class=\"empty-state\">This document is empty.</p>"
            : exportBody

        return """
        <!DOCTYPE html>
        <html lang="\(MarkdownRenderer.escape(language))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(MarkdownRenderer.escape(title))</title>
        <style>
        \(exportStylesheet(for: style))
        </style>
        </head>
        <body>
        <main>
        \(content)
        </main>
        </body>
        </html>
        """
    }

    private static func stylesheet(baseFontPointSize: CGFloat) -> String {
        // The web view's own text scaling is left alone; instead the root font
        // size is set from the app's current Dynamic Type size. That keeps the
        // rendered document in step with every other screen, and it means the
        // reader's accessibility text sizes are honoured rather than merely
        // approximated.
        let base = max(12, baseFontPointSize)

        return """
        :root {
          color-scheme: light dark;
          --page-bg: #f5f0e8;
          --panel-bg: #fffaf3;
          --accent: #23433a;
          --accent-soft: #d7e4dd;
          --border: #8b7f70;
          --text: #1f1b18;
          --muted: #534a42;
          --code-bg: #ece4d6;
          --link: #0d4f8f;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            --page-bg: #13100f;
            --panel-bg: #1c1816;
            --accent: #b7d7c9;
            --accent-soft: #2b342f;
            --border: #6f665d;
            --text: #f2ebe1;
            --muted: #d1c4b8;
            --code-bg: #312926;
            --link: #8dc2ff;
          }
        }

        * { box-sizing: border-box; }

        html {
          font-size: \(String(format: "%.1f", base))px;
          -webkit-text-size-adjust: none;
        }

        body {
          margin: 0;
          padding: 1rem;
          font-family: -apple-system, system-ui, Georgia, serif;
          line-height: 1.6;
          color: var(--text);
          background: var(--page-bg);
          overflow-wrap: break-word;
        }

        main { max-width: 42rem; margin: 0 auto; }

        h1, h2, h3, h4, h5, h6 {
          color: var(--accent);
          line-height: 1.25;
          margin: 1.5em 0 0.5em;
        }

        h1 { font-size: 1.8rem; }
        h2 { font-size: 1.5rem; }
        h3 { font-size: 1.3rem; }
        h4 { font-size: 1.15rem; }
        h5, h6 { font-size: 1rem; }

        :first-child { margin-top: 0; }

        p, li { margin: 0 0 0.85em; }

        a { color: var(--link); }

        code {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: 0.92em;
          padding: 0.1em 0.3em;
          border-radius: 0.25em;
          background: var(--code-bg);
        }

        pre {
          padding: 0.9em 1em;
          border-radius: 0.6em;
          background: var(--code-bg);
          overflow-x: auto;
        }

        pre code { padding: 0; background: none; }

        blockquote {
          margin: 0 0 1em;
          padding-left: 1em;
          border-left: 0.25em solid var(--border);
          color: var(--muted);
        }

        hr {
          border: 0;
          border-top: 1px solid var(--border);
          margin: 1.5em 0;
        }

        img { max-width: 100%; height: auto; }

        figure.tactile-graphic { margin: 1.5em 0; }
        figure.tactile-graphic figcaption {
          margin-top: 0.4em;
          color: var(--muted);
          font-style: italic;
        }

        .table-scroll {
          max-width: 100%;
          overflow-x: auto;
        }

        table {
          width: 100%;
          border-collapse: collapse;
          margin: 0 0 1em;
        }

        th, td {
          padding: 0.5em 0.7em;
          border: 1px solid var(--border);
          text-align: left;
        }

        th { background: var(--accent-soft); }
        .align-leading { text-align: left; }
        .align-center { text-align: center; }
        .align-trailing { text-align: right; }
        .image-fallback { font-style: italic; }

        ul.contains-task-list { list-style: none; padding-left: 1.2em; }
        li.task-list-item { margin-left: -1.2em; }
        .task-indicator {
          box-sizing: border-box;
          display: inline-block;
          position: relative;
          width: 1em;
          height: 1em;
          margin-right: 0.4em;
          border: 2px solid currentColor;
          border-radius: 0.15em;
          vertical-align: -0.1em;
        }
        .task-indicator.completed::after {
          content: "";
          position: absolute;
          left: 0.23em;
          top: 0.01em;
          width: 0.25em;
          height: 0.55em;
          border: solid currentColor;
          border-width: 0 0.14em 0.14em 0;
          transform: rotate(45deg);
        }
        .task-status { font-weight: 600; }

        .empty-state { color: var(--muted); font-style: italic; }

        /* A visible focus ring matters for anyone navigating the rendered
           document by keyboard or switch control. */
        a:focus-visible, :focus-visible {
          outline: 3px solid #a83b12;
          outline-offset: 2px;
        }

        @media (prefers-color-scheme: dark) {
          a:focus-visible, :focus-visible { outline-color: #f28d49; }
        }

        @media (prefers-reduced-motion: reduce) {
          * { animation: none !important; transition: none !important; }
        }
        """
    }

    /// Shared export CSS, independent of the in-app preview's text sizing.
    static func exportStylesheet(for style: HTMLExportStyle) -> String {
        style == .ghostWriter ? ghostWriterExportStylesheet : exportStylesheet
    }

    private static let ghostWriterExportStylesheet = """
    /* Colors */
    :root {
    \tcolor-scheme: light dark;
    \t--page-background: #f5f0e8;
    \t--text-color: #1f1b18;
    \t--heading-color: #23433a;
    \t--secondary-text-color: #534a42;
    \t--link-color: #0d4f8f;
    \t--code-background: #ece4d6;
    \t--table-header-background: #d7e4dd;
    \t--border-color: #827666;
    \t--focus-color: #a83b12;
    }

    @media (prefers-color-scheme: dark) {
    \t:root {
    \t\t--page-background: #13100f;
    \t\t--text-color: #f2ebe1;
    \t\t--heading-color: #b7d7c9;
    \t\t--secondary-text-color: #d1c4b8;
    \t\t--link-color: #8dc2ff;
    \t\t--code-background: #312926;
    \t\t--table-header-background: #2b342f;
    \t\t--border-color: #96897c;
    \t\t--focus-color: #f28d49;
    \t}
    }

    @media (forced-colors: active) {
    \t:root {
    \t\t--page-background: Canvas;
    \t\t--text-color: CanvasText;
    \t\t--heading-color: CanvasText;
    \t\t--secondary-text-color: CanvasText;
    \t\t--link-color: LinkText;
    \t\t--code-background: Canvas;
    \t\t--table-header-background: Canvas;
    \t\t--border-color: CanvasText;
    \t\t--focus-color: Highlight;
    \t}
    }

    @media print {
    \t:root {
    \t\tcolor-scheme: light;
    \t\t--page-background: #ffffff;
    \t\t--text-color: #000000;
    \t\t--heading-color: #000000;
    \t\t--secondary-text-color: #000000;
    \t\t--link-color: #000000;
    \t\t--code-background: #ffffff;
    \t\t--table-header-background: #ffffff;
    \t\t--border-color: #000000;
    \t\t--focus-color: #000000;
    \t}
    }

    /* Document */
    * {
    \tbox-sizing: border-box;
    }

    html {
    \tfont-size: 100%;
    \t-webkit-text-size-adjust: 100%;
    }

    body {
    \tmargin: 0;
    \tpadding: 1rem;
    \tfont-family: -apple-system, system-ui, Georgia, serif;
    \tline-height: 1.6;
    \tcolor: var(--text-color);
    \tbackground: var(--page-background);
    \toverflow-wrap: anywhere;
    }

    main {
    \tmax-width: 42rem;
    \tmargin: 0 auto;
    }

    h1, h2, h3, h4, h5, h6 {
    \tcolor: var(--heading-color);
    \tline-height: 1.25;
    \tmargin: 1.5em 0 0.5em;
    }

    h1 {
    \tfont-size: 1.8rem;
    }

    h2 {
    \tfont-size: 1.5rem;
    }

    h3 {
    \tfont-size: 1.3rem;
    }

    h4 {
    \tfont-size: 1.15rem;
    }

    h5, h6 {
    \tfont-size: 1rem;
    }

    :first-child {
    \tmargin-top: 0;
    }

    p, li {
    \tmargin: 0 0 0.85em;
    }

    a {
    \tcolor: var(--link-color);
    \ttext-decoration: underline;
    \ttext-underline-offset: 0.15em;
    }

    code {
    \tfont-family: ui-monospace, "SF Mono", Menlo, monospace;
    \tfont-size: 0.92em;
    \tpadding: 0.1em 0.3em;
    \tborder-radius: 0.25em;
    \tbackground: var(--code-background);
    }

    pre {
    \twhite-space: pre-wrap;
    \toverflow-wrap: anywhere;
    \tpadding: 0.9em 1em;
    \tborder-radius: 0.6em;
    \tbackground: var(--code-background);
    \toverflow-x: auto;
    }

    pre code {
    \tpadding: 0;
    \tbackground: none;
    }

    blockquote {
    \tmargin: 0 0 1em;
    \tpadding-inline-start: 1em;
    \tborder-inline-start: 0.25em solid var(--border-color);
    \tcolor: var(--secondary-text-color);
    }

    hr {
    \tborder: 0;
    \tborder-top: 1px solid var(--border-color);
    \tmargin: 1.5em 0;
    }

    img {
    \tmax-width: 100%;
    \theight: auto;
    }

    figure.tactile-graphic {
    \tmargin: 1.5em 0;
    }

    figure.tactile-graphic figcaption {
    \tmargin-top: 0.4em;
    \tcolor: var(--secondary-text-color);
    \tfont-style: italic;
    }

    .table-scroll {
    \tmax-width: 100%;
    \toverflow-x: auto;
    }

    table {
    \toverflow-wrap: anywhere;
    \twidth: 100%;
    \tborder-collapse: collapse;
    \tmargin: 0 0 1em;
    }

    th, td {
    \tpadding: 0.5em 0.7em;
    \tborder: 1px solid var(--border-color);
    \ttext-align: start;
    }

    th {
    \tbackground: var(--table-header-background);
    }

    .align-leading {
    \ttext-align: start;
    }

    .align-center {
    \ttext-align: center;
    }

    .align-trailing {
    \ttext-align: end;
    }

    .image-fallback {
    \tfont-style: italic;
    }

    ul.contains-task-list {
    \tlist-style: none;
    \tpadding-left: 1.2em;
    }

    li.task-list-item {
    \tmargin-left: -1.2em;
    }

    .task-indicator {
    \tbox-sizing: border-box;
    \tdisplay: inline-block;
    \tposition: relative;
    \twidth: 1em;
    \theight: 1em;
    \tmargin-right: 0.4em;
    \tborder: 2px solid currentColor;
    \tborder-radius: 0.15em;
    \tvertical-align: -0.1em;
    }

    .task-indicator.completed::after {
    \tcontent: "";
    \tposition: absolute;
    \tleft: 0.23em;
    \ttop: 0.01em;
    \twidth: 0.25em;
    \theight: 0.55em;
    \tborder: solid currentColor;
    \tborder-width: 0 0.14em 0.14em 0;
    \ttransform: rotate(45deg);
    }

    .task-status {
    \tfont-weight: 600;
    }

    .empty-state {
    \tcolor: var(--secondary-text-color);
    \tfont-style: italic;
    }

    a:focus-visible, :focus-visible {
    \toutline: 3px solid var(--focus-color);
    \toutline-offset: 2px;
    }

    section + section {
    \tmargin-block-start: 2rem;
    }

    summary {
    \tcursor: pointer;
    \tpadding-block: 0.5em;
    }

    summary h2 {
    \tdisplay: inline;
    \tmargin: 0;
    }

    details {
    \tmargin-block: 1.5em;
    }

    details > ul {
    \tmargin-block-start: 1em;
    }

    details a {
    \tdisplay: inline-block;
    \tpadding-block: 0.2em;
    }

    @media print {
    \tbody {
    \t\tpadding: 0;
    \t}
    \tmain {
    \t\tmax-width: none;
    \t}
    }
    """

    private static let exportStylesheet = """
    :root { color-scheme: light dark; }
    body {
    \tmargin: 0 auto;
    \tpadding: 2rem 1rem;
    \tmax-width: 42rem;
    \tfont-family: -apple-system, system-ui, Georgia, serif;
    \tline-height: 1.6;
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
    img { max-width: 100%; height: auto; }
    figure.tactile-graphic { margin: 1.5rem 0; }
    figure.tactile-graphic figcaption { margin-top: 0.4rem; font-style: italic; }
    pre { padding: 1rem; overflow-x: auto; background: rgba(127,127,127,0.12); border-radius: 0.5rem; }
    code { font-family: ui-monospace, Menlo, monospace; }
    blockquote { margin-inline: 0; padding-left: 1rem; border-left: 0.25rem solid currentColor; }
    .table-scroll { max-width: 100%; overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 0.5rem 0.7rem; border: 1px solid currentColor; text-align: left; }
    .align-leading { text-align: left; }
    .align-center { text-align: center; }
    .align-trailing { text-align: right; }
    .image-fallback { font-style: italic; }
    ul.contains-task-list { list-style: none; padding-left: 1.2em; }
    li.task-list-item { margin-left: -1.2em; }
    .task-indicator {
    \tbox-sizing: border-box;
    \tdisplay: inline-block;
    \tposition: relative;
    \twidth: 1em;
    \theight: 1em;
    \tmargin-right: 0.4em;
    \tborder: 2px solid currentColor;
    \tborder-radius: 0.15em;
    \tvertical-align: -0.1em;
    }
    .task-indicator.completed::after {
    \tcontent: "";
    \tposition: absolute;
    \tleft: 0.23em;
    \ttop: 0.01em;
    \twidth: 0.25em;
    \theight: 0.55em;
    \tborder: solid currentColor;
    \tborder-width: 0 0.14em 0.14em 0;
    \ttransform: rotate(45deg);
    }
    .task-status { font-weight: 600; }
    """
}
