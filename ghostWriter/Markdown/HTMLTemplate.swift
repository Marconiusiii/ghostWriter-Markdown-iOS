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
import UIKit

enum HTMLTemplate {

    /// A full document for display in the in-app web view.
    ///
    /// - Parameters:
    ///   - title: Used only as the HTML document title.
    ///   - body: Rendered HTML fragment.
    ///   - baseFontPointSize: The reader's current body text size, taken from
    ///     the trait environment so the web view matches the rest of the app.
    static func document(
        title: String,
        body: String,
        baseFontPointSize: CGFloat
    ) -> String {
        let content = body.isEmpty
            ? "<p class=\"empty-state\">This document is empty.</p>"
            : body

        return """
        <!DOCTYPE html>
        <html lang="en">
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
    static func exportDocument(title: String, body: String) -> String {
        let content = body.isEmpty
            ? "<p class=\"empty-state\">This document is empty.</p>"
            : body

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(MarkdownRenderer.escape(title))</title>
        <style>
        \(exportStylesheet)
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

        /* Tables scroll inside their own container so the page body never
           scrolls sideways, which is disorienting when zoomed in. */
        table {
          width: 100%;
          border-collapse: collapse;
          margin: 0 0 1em;
          display: block;
          overflow-x: auto;
        }

        th, td {
          padding: 0.5em 0.7em;
          border: 1px solid var(--border);
          text-align: left;
        }

        th { background: var(--accent-soft); }

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

    private static let exportStylesheet = """
    :root { color-scheme: light dark; }
    body {
      margin: 0 auto;
      padding: 2rem 1rem;
      max-width: 42rem;
      font-family: -apple-system, system-ui, Georgia, serif;
      line-height: 1.6;
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
    img { max-width: 100%; height: auto; }
    pre { padding: 1rem; overflow-x: auto; background: rgba(127,127,127,0.12); border-radius: 0.5rem; }
    code { font-family: ui-monospace, Menlo, monospace; }
    blockquote { margin-inline: 0; padding-left: 1rem; border-left: 0.25rem solid currentColor; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 0.5rem 0.7rem; border: 1px solid currentColor; text-align: left; }
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
    """
}
