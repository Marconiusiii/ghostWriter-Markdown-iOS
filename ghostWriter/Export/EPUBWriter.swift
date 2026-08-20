//
//  EPUBWriter.swift
//  ghostWriter
//
//  Writes an EPUB 3 file: a zip containing XHTML, a package manifest, and a
//  navigation document.
//
//  EPUB is the most accessible of the export formats, because it reflows. A
//  reader sets their own text size and the content adapts, where a PDF's page
//  is fixed. The semantics that matter — headings, lists, table headers, image
//  alternative text — are carried by the XHTML itself, so the work here is
//  producing correct markup and a correct package around it.
//

import Foundation

nonisolated enum EPUBWriter {

    static func write(
        title: String,
        markdown: String,
        sourceDirectory: URL? = nil
    ) throws -> Data {
        let document = MarkdownDocumentParser.parse(markdown)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookTitle = trimmedTitle.isEmpty ? "Document" : trimmedTitle

        // A stable identifier is required by the format. It is generated per
        // export rather than stored, because two exports of an edited document
        // are genuinely different publications.
        let identifier = "urn:uuid:\(UUID().uuidString.lowercased())"
        let language = documentLanguage()

        var entries: [String: Data] = [:]

        // mimetype must be the first entry and stored uncompressed. Reading
        // systems identify the file by reading those bytes at a fixed offset,
        // so a deflated mimetype makes the book unrecognisable.
        entries["mimetype"] = Data("application/epub+zip".utf8)

        entries["META-INF/container.xml"] = Data(containerXML.utf8)

        let imageResources = collectImageResources(document, sourceDirectory: sourceDirectory)

        entries["OEBPS/content.opf"] = Data(packageDocument(
            title: bookTitle,
            identifier: identifier,
            language: language,
            images: imageResources.images
        ).utf8)

        entries["OEBPS/nav.xhtml"] = Data(navigationDocument(
            title: bookTitle,
            language: language,
            document: document,
            includeTitleHeading: !startsWithMatchingHeading(document, title: bookTitle)
        ).utf8)

        entries["OEBPS/style.css"] = Data(stylesheet.utf8)

        entries["OEBPS/content.xhtml"] = Data(contentDocument(
            title: bookTitle,
            language: language,
            document: document,
            includeTitleHeading: !startsWithMatchingHeading(document, title: bookTitle),
            imageResources: imageResources
        ).utf8)

        for image in imageResources.images {
            entries["OEBPS/\(image.href)"] = image.data
        }

        return try EPUBPackage.create(entries: entries)
    }

    private static func documentLanguage() -> String {
        Locale.preferredLanguages.first
            ?? Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    private static func startsWithMatchingHeading(
        _ document: ExportDocument,
        title: String
    ) -> Bool {
        guard case .heading(_, let content)? = document.blocks.first else { return false }
        return content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(title) == .orderedSame
    }

    // MARK: - Package parts

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
    </container>
    """

    /// Minimal styling. Sizes are relative so the reader's own text-size
    /// setting stays in charge — fixing them in pixels would override the one
    /// accessibility control EPUB reliably offers.
    private static let stylesheet = """
    body { line-height: 1.5; margin: 0 5%; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
    code, pre { font-family: monospace; }
    pre { white-space: pre-wrap; overflow-wrap: break-word; background: #f4f4f4; padding: 0.6em; }
    blockquote { border-left: 3px solid #767676; margin-left: 0; padding-left: 1em; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #767676; padding: 0.3em 0.5em; text-align: left; }
    img { max-width: 100%; height: auto; }
    .task-state { font-style: italic; }
    """

    private static func packageDocument(
        title: String,
        identifier: String,
        language: String,
        images: [EmbeddedImage]
    ) -> String {
        let manifestImages = images.map { image in
            "<item id=\"\(image.id)\" href=\"\(image.href)\" media-type=\"\(image.mediaType)\"/>"
        }.joined(separator: "\n")

        // dcterms:modified is mandatory in EPUB 3 and must be in this exact
        // form; a reading system rejects the package without it.
        let modified = ISO8601DateFormatter().string(from: Date())

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="\(escape(language))">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="book-id">\(escape(identifier))</dc:identifier>
        <dc:title>\(escape(title))</dc:title>
        <dc:language>\(escape(language))</dc:language>
        <meta property="dcterms:modified">\(modified)</meta>
        <meta property="schema:accessMode">textual</meta>
        <meta property="schema:accessModeSufficient">textual</meta>
        <meta property="schema:accessibilityFeature">structuralNavigation</meta>
        <meta property="schema:accessibilityFeature">tableOfContents</meta>
        <meta property="schema:accessibilityHazard">none</meta>
        <meta property="schema:accessibilitySummary">This publication uses semantic headings, lists, and table markup throughout, and provides alternative text for images.</meta>
        </metadata>
        <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
        <item id="style" href="style.css" media-type="text/css"/>
        \(manifestImages)
        </manifest>
        <spine>
        <itemref idref="content"/>
        </spine>
        </package>
        """
    }

    /// The navigation document doubles as the table of contents. Every heading
    /// becomes an entry, which is what gives a reading system's "go to chapter"
    /// control something to move between.
    private static func navigationDocument(
        title: String,
        language: String,
        document: ExportDocument,
        includeTitleHeading: Bool
    ) -> String {
        let headings = document.headings(startingAt: includeTitleHeading ? 2 : 1)
        let items = navigationList(headings)

        // A table of contents with no entries is invalid, so a document without
        // headings gets a single entry pointing at its start.
        let contents = items.isEmpty
            ? "<ol>\n<li><a href=\"content.xhtml\">\(escape(title))</a></li>\n</ol>"
            : items

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(escape(language))" lang="\(escape(language))">
        <head>
        <meta charset="utf-8"/>
        <title>Contents</title>
        </head>
        <body>
        <nav epub:type="toc" id="toc" role="doc-toc">
        <h1>Contents</h1>
        \(contents)
        </nav>
        </body>
        </html>
        """
    }

    private final class NavigationNode {
        let heading: ExportHeading
        var children: [NavigationNode] = []

        init(_ heading: ExportHeading) {
            self.heading = heading
        }
    }

    private static func navigationList(_ headings: [ExportHeading]) -> String {
        var roots: [NavigationNode] = []
        var stack: [NavigationNode] = []

        for heading in headings {
            while let last = stack.last, last.heading.level >= heading.level {
                stack.removeLast()
            }
            let node = NavigationNode(heading)
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }

        func render(_ nodes: [NavigationNode]) -> String {
            guard !nodes.isEmpty else { return "" }
            let items = nodes.map { node in
                let text = node.heading.content.plainText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let children = render(node.children)
                return "<li><a href=\"content.xhtml#\(node.heading.identifier)\">\(escape(text))</a>\(children)</li>"
            }.joined(separator: "\n")
            return "<ol>\n\(items)\n</ol>"
        }

        return render(roots)
    }

    // MARK: - Content

    private static func contentDocument(
        title: String,
        language: String,
        document: ExportDocument,
        includeTitleHeading: Bool,
        imageResources: ImageResources
    ) -> String {
        var builder = ContentBuilder(imageResources: imageResources)
        var body = ""

        if includeTitleHeading {
            builder.headingCounter += 1
            body += "<h1 id=\"heading-\(builder.headingCounter)\">\(escape(title))</h1>\n"
        }

        body += builder.render(document.blocks)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(escape(language))" lang="\(escape(language))">
        <head>
        <meta charset="utf-8"/>
        <title>\(escape(title))</title>
        <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Renders blocks to XHTML. This is deliberately separate from
    /// MarkdownRenderer: EPUB requires well-formed XML, so void elements need
    /// explicit closing and unclosed tags are a hard error rather than
    /// something a browser silently repairs.
    private struct ContentBuilder {
        var headingCounter = 0
        let imageResources: ImageResources

        mutating func render(_ blocks: [ExportBlock]) -> String {
            var output = ""

            for block in blocks {
                switch block {
                case .heading(let level, let content):
                    headingCounter += 1
                    let clamped = min(max(level, 1), 6)
                    output += "<h\(clamped) id=\"heading-\(headingCounter)\">"
                        + inline(content) + "</h\(clamped)>\n"

                case .paragraph(let content):
                    guard !content.isEffectivelyEmpty else { continue }
                    output += "<p>" + inline(content) + "</p>\n"

                case .list(let list):
                    output += renderList(list)

                case .table(let table):
                    output += renderTable(table)

                case .blockQuote(let children):
                    output += "<blockquote>\n" + render(children) + "</blockquote>\n"

                case .codeBlock(let language, let code):
                    let attribute = language.map {
                        " class=\"language-\(escape($0))\""
                    } ?? ""
                    output += "<pre><code\(attribute)>" + escape(code) + "</code></pre>\n"

                case .thematicBreak:
                    output += "<hr/>\n"
                }
            }

            return output
        }

        mutating func renderList(_ list: ExportList) -> String {
            let tag = list.isOrdered ? "ol" : "ul"
            // An ordered list starting somewhere other than one keeps its
            // numbering, so a continued list still reads correctly.
            let startAttribute = list.isOrdered && list.start != 1
                ? " start=\"\(list.start)\""
                : ""

            var output = "<\(tag)\(startAttribute)>\n"

            for item in list.items {
                output += "<li>"
                // Task state is stated in words. A checkbox character would be
                // read as a symbol name or skipped entirely, and this list is
                // not interactive, so a real input would be misleading.
                if let state = item.taskState {
                    output += "<span class=\"task-state\">\(escape(state.spokenPrefix))</span> "
                }
                output += inline(item.content)
                if !item.children.isEmpty {
                    output += "\n" + render(item.children)
                }
                output += "</li>\n"
            }

            return output + "</\(tag)>\n"
        }

        mutating func renderTable(_ table: ExportTable) -> String {
            var output = "<table>\n"

            func alignmentStyle(_ column: Int) -> String {
                switch table.alignment(forColumn: column) {
                case .natural: return ""
                case .leading: return " style=\"text-align:left\""
                case .center: return " style=\"text-align:center\""
                case .trailing: return " style=\"text-align:right\""
                }
            }

            if !table.headers.isEmpty, !table.headers.allSatisfy(\.isEffectivelyEmpty) {
                output += "<thead>\n<tr>"
                for (column, cell) in table.headers.enumerated() {
                    // scope="col" is what associates a data cell with its
                    // column heading when a screen reader reads the table.
                    output += "<th scope=\"col\"\(alignmentStyle(column))>"
                        + inline(cell) + "</th>"
                }
                output += "</tr>\n</thead>\n"
            }

            if !table.rows.isEmpty {
                output += "<tbody>\n"
                for row in table.rows {
                    output += "<tr>"
                    for (column, cell) in row.enumerated() {
                        output += "<td\(alignmentStyle(column))>" + inline(cell) + "</td>"
                    }
                    output += "</tr>\n"
                }
                output += "</tbody>\n"
            }

            return output + "</table>\n"
        }

        func inline(_ spans: [ExportInline]) -> String {
            var output = ""

            for span in spans {
                switch span {
                case .text(let value):
                    output += escape(value)
                case .emphasis(let children):
                    output += "<em>" + inline(children) + "</em>"
                case .strong(let children):
                    output += "<strong>" + inline(children) + "</strong>"
                case .strikethrough(let children):
                    output += "<del>" + inline(children) + "</del>"
                case .underline(let children):
                    output += "<u>" + inline(children) + "</u>"
                case .code(let value):
                    output += "<code>" + escape(value) + "</code>"
                case .link(let destination, let content):
                    let label = inline(content)
                    if let href = EPUBWriter.safeLinkHref(destination) {
                        output += "<a href=\"\(escape(href))\">" + label + "</a>"
                    } else {
                        output += label
                    }
                case .image(let image):
                    output += renderImage(image)
                case .lineBreak:
                    output += "<br/>"
                }
            }

            return output
        }

        func renderImage(_ image: ExportImage) -> String {
            guard let href = imageResources.hrefBySource[image.source] else {
                guard !image.isDecorative else { return "" }
                return "<span class=\"image-description\">Image: \(escape(image.alternativeText ?? ""))</span>"
            }
            if image.isDecorative { return "<img src=\"\(escape(href))\" alt=\"\"/>" }
            return "<img src=\"\(escape(href))\" alt=\"\(escape(image.alternativeText ?? ""))\"/>"
        }
    }

    // MARK: - Images

    nonisolated struct EmbeddedImage {
        let id: String
        let href: String
        let mediaType: String
        let data: Data
    }

    nonisolated struct ImageResources {
        let images: [EmbeddedImage]
        let hrefBySource: [String: String]
    }

    static func safeLinkHref(_ destination: String) -> String? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto", "tel", "sms"].contains(scheme)
        else { return nil }
        return trimmed
    }

    /// Keeps the readable portion of an asset name while removing characters
    /// that are unsafe in a package path.
    private static func sanitizedFileName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    /// Gathers the local images a document refers to, so they can be embedded.
    /// An EPUB that links to files on the device would be empty on any other
    /// machine, so the bytes have to travel with the book.
    static func collectImageResources(
        _ document: ExportDocument,
        sourceDirectory: URL?
    ) -> ImageResources {
        var sources: [String] = []
        collectImageSources(document.blocks, into: &sources)

        var images: [EmbeddedImage] = []
        var hrefBySource: [String: String] = [:]
        let root = sourceDirectory?.standardizedFileURL.resolvingSymlinksInPath()

        for source in sources {
            guard hrefBySource[source] == nil, let root else { continue }

            let decoded = source.removingPercentEncoding ?? source
            guard !decoded.hasPrefix("/"), URL(string: decoded)?.scheme == nil else { continue }
            let relativeComponents = decoded.split(separator: "/", omittingEmptySubsequences: true)
            guard let assetDirectory = relativeComponents.first,
                  assetDirectory.hasPrefix(".ghostwriter-assets-") else { continue }

            let url = root.appendingPathComponent(decoded).standardizedFileURL
                .resolvingSymlinksInPath()
            let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard url.path.hasPrefix(rootPrefix),
                  let mediaType = mediaType(for: url.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty else { continue }

            let href = "images/image-\(images.count + 1)-\(sanitizedFileName(decoded))"
            hrefBySource[source] = href
            images.append(EmbeddedImage(
                id: "img-\(images.count + 1)",
                href: href,
                mediaType: mediaType,
                data: data
            ))
        }

        return ImageResources(images: images, hrefBySource: hrefBySource)
    }

    private static func collectImageSources(
        _ blocks: [ExportBlock],
        into sources: inout [String]
    ) {
        for block in blocks {
            switch block {
            case .heading(_, let content), .paragraph(let content):
                collectImageSources(inline: content, into: &sources)
            case .list(let list):
                for item in list.items {
                    collectImageSources(inline: item.content, into: &sources)
                    collectImageSources(item.children, into: &sources)
                }
            case .table(let table):
                for cell in table.headers {
                    collectImageSources(inline: cell, into: &sources)
                }
                for row in table.rows {
                    for cell in row {
                        collectImageSources(inline: cell, into: &sources)
                    }
                }
            case .blockQuote(let children):
                collectImageSources(children, into: &sources)
            case .codeBlock, .thematicBreak:
                continue
            }
        }
    }

    private static func collectImageSources(
        inline spans: [ExportInline],
        into sources: inout [String]
    ) {
        for span in spans {
            switch span {
            case .image(let image):
                sources.append(image.source)
            case .emphasis(let children),
                 .strong(let children),
                 .strikethrough(let children),
                 .underline(let children),
                 .link(_, let children):
                collectImageSources(inline: children, into: &sources)
            case .text, .code, .lineBreak:
                continue
            }
        }
    }

    private static func mediaType(for pathExtension: String) -> String? {
        switch pathExtension {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "png": return "image/png"
        default: return nil
        }
    }

    // MARK: - Escaping

    /// XML escaping. Stricter than the HTML export's: an unescaped ampersand is
    /// merely wrong in HTML but makes an EPUB unopenable.
    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
