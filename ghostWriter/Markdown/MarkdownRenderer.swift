//
//  MarkdownRenderer.swift
//  ghostWriter
//
//  Renders the shared parsed document model as semantic HTML. Keeping parsing
//  in MarkdownDocumentParser means HTML, plain text, EPUB, Word, PDF, and the
//  braille formats agree about the structure of the same Markdown source.
//

import Foundation

nonisolated enum MarkdownRenderer {
    static func html(
        from markdown: String,
        title: String? = nil,
        sourceDirectory: URL? = nil,
        embedLocalImages: Bool = false
    ) -> String {
        let document = MarkdownDocumentParser.parse(markdown)
        var blocks = document.blocks
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedTitle.isEmpty,
           !containsLevelOneHeading(blocks) {
            blocks.insert(.heading(level: 1, content: [.text(trimmedTitle)]), at: 0)
        }

        var output = Renderer(
            sourceDirectory: sourceDirectory,
            embedLocalImages: embedLocalImages
        ).render(blocks)

        if document.blocks.isEmpty {
            output += "<p class=\"empty-state\">This document is empty.</p>"
        }
        return output
    }

    private static func containsLevelOneHeading(_ blocks: [ExportBlock]) -> Bool {
        blocks.contains { block in
            switch block {
            case .heading(let level, _):
                return level == 1
            case .blockQuote(let children):
                return containsLevelOneHeading(children)
            case .list(let list):
                return list.items.contains { containsLevelOneHeading($0.children) }
            case .paragraph, .table, .codeBlock, .thematicBreak:
                return false
            }
        }
    }

    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// Links remain active only for destinations appropriate to a shared web
    /// document. Unsafe or active schemes are rendered as ordinary link text.
    static func safeLinkDestination(_ destination: String) -> String? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("//"),
              !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 }) else {
            return nil
        }
        if trimmed.hasPrefix("#") { return trimmed }

        guard let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased() else {
            return trimmed.hasPrefix("/") ? nil : trimmed
        }
        return ["https", "http", "mailto", "tel", "sms"].contains(scheme)
            ? trimmed
            : nil
    }

    private struct Renderer {
        var sourceDirectory: URL?
        var embedLocalImages: Bool

        func render(_ blocks: [ExportBlock]) -> String {
            blocks.map(render).joined()
        }

        private func render(_ block: ExportBlock) -> String {
            switch block {
            case .heading(let level, let content):
                return "<h\(level)>\(inline(content))</h\(level)>"
            case .paragraph(let content):
                let body = inline(content)
                return body.isEmpty ? "" : "<p>\(body)</p>"
            case .list(let list):
                return renderList(list)
            case .table(let table):
                return renderTable(table)
            case .blockQuote(let children):
                return "<blockquote>\(render(children))</blockquote>"
            case .codeBlock(let language, let code):
                let languageClass = language.flatMap(safeLanguageClass)
                    .map { " class=\"language-\($0)\"" } ?? ""
                return "<pre><code\(languageClass)>\(MarkdownRenderer.escape(code))</code></pre>"
            case .thematicBreak:
                return "<hr>"
            }
        }

        private func renderList(_ list: ExportList) -> String {
            let tag = list.isOrdered ? "ol" : "ul"
            var attributes = list.isOrdered && list.start != 1
                ? " start=\"\(list.start)\""
                : ""
            if list.items.contains(where: { $0.taskState != nil }) {
                attributes += " class=\"contains-task-list\""
            }

            let items = list.items.map { item -> String in
                let itemClass = item.taskState == nil ? "" : " class=\"task-list-item\""
                let taskPrefix: String
                if let state = item.taskState {
                    let completedClass = state == .completed ? " completed" : ""
                    taskPrefix = "<span class=\"task-indicator\(completedClass)\"></span>"
                        + "<span class=\"task-status\">\(state.spokenPrefix)</span> "
                } else {
                    taskPrefix = ""
                }
                return "<li\(itemClass)>\(taskPrefix)\(inline(item.content))"
                    + "\(render(item.children))</li>"
            }.joined()

            return "<\(tag)\(attributes)>\(items)</\(tag)>"
        }

        private func renderTable(_ table: ExportTable) -> String {
            guard table.columnCount > 0 else { return "" }

            func cells(_ row: [[ExportInline]]) -> [[ExportInline]] {
                (0..<table.columnCount).map { column in
                    column < row.count ? row[column] : []
                }
            }

            var output = "<div class=\"table-scroll\"><table>"
            if !table.headers.isEmpty,
               !table.headers.allSatisfy(\.isEffectivelyEmpty) {
                output += "<thead><tr>"
                for (column, cell) in cells(table.headers).enumerated() {
                    output += "<th scope=\"col\"\(alignmentClass(table.alignment(forColumn: column)))>"
                        + "\(inline(cell))</th>"
                }
                output += "</tr></thead>"
            }

            if !table.rows.isEmpty {
                output += "<tbody>"
                for row in table.rows {
                    output += "<tr>"
                    for (column, cell) in cells(row).enumerated() {
                        output += "<td\(alignmentClass(table.alignment(forColumn: column)))>"
                            + "\(inline(cell))</td>"
                    }
                    output += "</tr>"
                }
                output += "</tbody>"
            }
            return output + "</table></div>"
        }

        private func alignmentClass(_ alignment: ExportAlignment) -> String {
            switch alignment {
            case .natural: return ""
            case .leading: return " class=\"align-leading\""
            case .center: return " class=\"align-center\""
            case .trailing: return " class=\"align-trailing\""
            }
        }

        private func inline(_ spans: [ExportInline]) -> String {
            spans.map { span in
                switch span {
                case .text(let value):
                    return MarkdownRenderer.escape(value)
                case .emphasis(let children):
                    return "<em>\(inline(children))</em>"
                case .strong(let children):
                    return "<strong>\(inline(children))</strong>"
                case .strikethrough(let children):
                    return "<del>\(inline(children))</del>"
                case .underline(let children):
                    return "<u>\(inline(children))</u>"
                case .code(let value):
                    return "<code>\(MarkdownRenderer.escape(value))</code>"
                case .link(let destination, let content):
                    let label = inline(content)
                    guard let href = MarkdownRenderer.safeLinkDestination(destination) else {
                        return label
                    }
                    return "<a href=\"\(MarkdownRenderer.escape(href))\">\(label)</a>"
                case .image(let image):
                    return renderImage(image)
                case .lineBreak:
                    return "<br>"
                }
            }.joined()
        }

        private func renderImage(_ image: ExportImage) -> String {
            let source: String?
            if let resource = ExportImageResource.resolveManagedAsset(
                source: image.source,
                sourceDirectory: sourceDirectory
            ) {
                source = embedLocalImages
                    ? "data:\(resource.mediaType);base64,\(resource.data.base64EncodedString())"
                    : image.source
            } else {
                source = safeRemoteImageSource(image.source)
            }

            if image.isTactile {
                return renderTactileGraphic(image, source: source)
            }
            guard let source else { return imageFallback(image) }
            let alt = MarkdownRenderer.escape(image.alternativeText ?? "")
            let title = image.title.map {
                " title=\"\(MarkdownRenderer.escape($0))\""
            } ?? ""
            return "<img src=\"\(MarkdownRenderer.escape(source))\" alt=\"\(alt)\"\(title)>"
        }

        private func renderTactileGraphic(
            _ image: ExportImage,
            source: String?
        ) -> String {
            let description = image.alternativeText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let caption = description.isEmpty
                ? "Tactile graphic"
                : "Tactile graphic: \(description)"
            let escapedCaption = MarkdownRenderer.escape(caption)

            guard let source else {
                return "<span class=\"image-fallback\">\(escapedCaption)</span>"
            }
            let title = image.title.map {
                " title=\"\(MarkdownRenderer.escape($0))\""
            } ?? ""
            return "<figure class=\"tactile-graphic\">"
                + "<img src=\"\(MarkdownRenderer.escape(source))\" alt=\"\"\(title)>"
                + "<figcaption>\(escapedCaption)</figcaption></figure>"
        }

        private func safeRemoteImageSource(_ source: String) -> String? {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else {
                return nil
            }
            return trimmed
        }

        private func imageFallback(_ image: ExportImage) -> String {
            guard let alternativeText = image.alternativeText,
                  !alternativeText.isEmpty else { return "" }
            return "<span class=\"image-fallback\">Image: "
                + "\(MarkdownRenderer.escape(alternativeText))</span>"
        }

        private func safeLanguageClass(_ language: String) -> String? {
            let allowed = CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "_+-")
            )
            guard !language.isEmpty,
                  language.unicodeScalars.allSatisfy(allowed.contains) else {
                return nil
            }
            return language
        }
    }
}
