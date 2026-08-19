//
//  EBrailleWriter.swift
//  ghostWriter
//
//  Writes an eBraille 1.0 publication: braille in an EPUB 3 container.
//
//  eBraille is EPUB underneath, so this shares the container writer with the
//  EPUB export, but it is not simply EPUB with different text. The differences
//  are structural and each one is a conformance requirement:
//
//  - The package document must be `package.opf` and the navigation document
//    `index.html`, both at the publication root, where EPUB lets you name and
//    place them freely.
//  - Braille-specific metadata is mandatory, one instance of each property.
//  - Renderable text must be Unicode braille patterns, including alternative
//    text on images.
//  - The reading system controls rendering, so the stylesheet must not set
//    fonts, sizes, colours, or decoration.
//  - List markers cannot be left to the reading system to generate, so
//    numbering is written into the content.
//
//  Lines are deliberately not wrapped. A braille display's width is a property
//  of the reader's hardware and preference, and eBraille leaves the reflowing
//  to the reading system — hard-wrapping here would bake in a line length that
//  is wrong for most readers.
//

import Foundation

nonisolated enum EBrailleWriter {

    static func write(
        title: String,
        markdown: String,
        metadata: EBrailleMetadata,
        translator: BrailleTranslator,
        sourceDirectory: URL? = nil
    ) async throws -> Data {
        let document = MarkdownDocumentParser.parse(markdown)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookTitle = trimmedTitle.isEmpty ? "Document" : trimmedTitle

        // The language comes from the translation table, not the device.
        // These tables are UEB, which is English: a French-locale device
        // exporting an English UEB transcription previously declared
        // `fr-Brai-FR`, describing a French braille document that the file is
        // not. The region is still taken from the device, since it is a
        // regional preference rather than a claim about the braille code.
        let language = BrailleLanguageTag.brailleTag(
            from: metadata.grade.languageTag,
            regionFrom: BrailleLanguageTag.currentBrailleTag()
        )
        let identifier = "urn:uuid:\(UUID().uuidString.lowercased())"

        // Every piece of readable text is translated up front. Doing it here,
        // rather than inside the markup builder, keeps the translation calls
        // off the recursive rendering path where they would be awaited
        // hundreds of times over.
        var translations = TranslationTable()
        try await translations.gather(
            from: document,
            title: bookTitle,
            grade: metadata.grade,
            translator: translator
        )

        var entries: [String: Data] = [:]
        entries["mimetype"] = Data("application/epub+zip".utf8)
        entries["META-INF/container.xml"] = Data(containerXML.utf8)

        let images = EPUBWriter.collectEmbeddedImages(
            document,
            sourceDirectory: sourceDirectory
        )

        entries["package.opf"] = Data(packageDocument(
            title: bookTitle,
            identifier: identifier,
            language: language,
            metadata: metadata,
            images: images,
            translations: translations
        ).utf8)

        entries["index.html"] = Data(navigationDocument(
            title: bookTitle,
            language: language,
            document: document,
            translations: translations
        ).utf8)

        entries["style.css"] = Data(stylesheet.utf8)

        entries["content.xhtml"] = Data(contentDocument(
            title: bookTitle,
            language: language,
            document: document,
            translations: translations,
            includeTitleHeading: !startsWithMatchingHeading(document, title: bookTitle)
        ).utf8)

        for image in images {
            entries[image.href] = image.data
        }

        return try EPUBPackage.create(entries: entries)
    }

    private static func startsWithMatchingHeading(
        _ document: ExportDocument,
        title: String
    ) -> Bool {
        guard case .heading(_, let content)? = document.blocks.first else { return false }
        return content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(title) == .orderedSame
    }

    // MARK: - Translation

    /// Print text mapped to its braille, gathered before rendering begins.
    ///
    /// Translation is an actor call, so it cannot happen inside the synchronous
    /// markup builders. Collecting every string first turns what would be
    /// hundreds of awaits scattered through a recursive render into one pass.
    struct TranslationTable {
        private var braille: [String: String] = [:]

        mutating func gather(
            from document: ExportDocument,
            title: String,
            grade: BrailleGrade,
            translator: BrailleTranslator
        ) async throws {
            var strings = Set<String>()
            strings.insert(title)
            Self.collect(document.blocks, into: &strings)

            for string in strings {
                // Translate the string as it stands, not a trimmed copy.
                // Leading and trailing spaces are word boundaries: a run like
                // "This text is " sits directly against an emphasised run, and
                // trimming the space here joined them into "isbold". liblouis
                // renders a space as U+2800 and preserves it, so the only
                // thing trimming achieved was losing it.
                guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                braille[string] = try await translator.translate(string, grade: grade)
            }
        }

        /// Braille for a print string. Untranslated text never reaches the
        /// output: an empty result is correct for whitespace, and anything
        /// else would be a print string appearing in a braille document.
        func callAsFunction(_ text: String) -> String {
            braille[text] ?? ""
        }

        private static func collect(_ blocks: [ExportBlock], into strings: inout Set<String>) {
            for block in blocks {
                switch block {
                case .heading(_, let content), .paragraph(let content):
                    collect(inline: content, into: &strings)
                case .list(let list):
                    for item in list.items {
                        if let state = item.taskState {
                            strings.insert(state.spokenPrefix)
                        }
                        collect(inline: item.content, into: &strings)
                        collect(item.children, into: &strings)
                    }
                case .table(let table):
                    for cell in table.headers { collect(inline: cell, into: &strings) }
                    for row in table.rows {
                        for cell in row { collect(inline: cell, into: &strings) }
                    }
                case .blockQuote(let children):
                    collect(children, into: &strings)
                case .codeBlock(_, let code):
                    strings.insert(code)
                case .thematicBreak:
                    continue
                }
            }
        }

        private static func collect(inline spans: [ExportInline], into strings: inout Set<String>) {
            for span in spans {
                switch span {
                case .text(let value):
                    strings.insert(value)
                case .code(let value):
                    strings.insert(value)
                case .emphasis(let children),
                     .strong(let children),
                     .strikethrough(let children),
                     .underline(let children),
                     .link(_, let children):
                    collect(inline: children, into: &strings)
                case .image(let image):
                    // Alternative text is renderable, so it is translated too.
                    // A print caption inside a braille document would be read
                    // as meaningless cell patterns.
                    if let alternative = image.alternativeText {
                        strings.insert(alternative)
                    }
                case .lineBreak:
                    continue
                }
            }
        }
    }

    // MARK: - Package parts

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
    <rootfile full-path="package.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
    </container>
    """

    /// Layout following BANA *Braille Formats* (2016), the formatting standard
    /// for North American braille transcription.
    ///
    /// Positions are in `ch`, which is the only unit that means anything here:
    /// eBraille requires a reading system to guarantee that `1ch` is the
    /// cell-to-cell distance and `1em` the line-to-line distance. A margin in
    /// `em` — as this used to be — indents by *lines*, so it lands on an
    /// arbitrary cell. Braille Formats is written entirely in cell positions,
    /// so `ch` is what expresses it.
    ///
    /// Rendering is still left to the reading system: no font, size, colour,
    /// or decoration is set. Only the positions BANA specifies.
    ///
    /// The conventional notation below is "start-runover": 3-1 means the first
    /// line begins in cell 3 and continued lines return to cell 1. In CSS that
    /// is a `margin-left` for the runover and a `text-indent` for the
    /// difference on the first line.
    private static let stylesheet = """
    body { margin: 0; }

    /* Headings, in BANA's hierarchy: centered, then cell 5, then cell 7.
       A centered heading is preceded and followed by a blank line; cell-5
       and cell-7 headings are preceded by one but not followed. */
    h1 { text-align: center; margin: 1em 0; }
    h2 { margin: 1em 0 0 0; padding-left: 4ch; }
    h3, h4, h5, h6 { margin: 1em 0 0 0; padding-left: 6ch; }

    /* Body paragraphs are 3-1: first line in cell 3, runover in cell 1. */
    p { margin: 0; text-indent: 2ch; }

    /* Lists are 1-3: item begins in cell 1, runover two cells right. Each
       nested level moves two cells further, with runovers following. */
    ol, ul { margin: 1em 0; padding-left: 0; list-style-type: none; }
    li { margin: 0; padding-left: 2ch; text-indent: -2ch; }
    li ol, li ul { margin: 0; padding-left: 2ch; }

    /* Displayed material sits two cells in from the surrounding margin. */
    blockquote { margin: 1em 0; padding-left: 2ch; }

    /* Preformatted text keeps its own line breaks rather than reflowing. */
    pre { margin: 1em 0; padding-left: 2ch; white-space: pre-wrap; }

    table { border-collapse: collapse; }
    td, th { padding: 0 1ch 0 0; text-align: left; vertical-align: top; }
    """

    private static func packageDocument(
        title: String,
        identifier: String,
        language: String,
        metadata: EBrailleMetadata,
        images: [EPUBWriter.EmbeddedImage],
        translations: TranslationTable
    ) -> String {
        let manifestImages = images.map { image in
            "<item id=\"\(image.id)\" href=\"\(image.href)\" media-type=\"\(image.mediaType)\"/>"
        }.joined(separator: "\n")

        let modified = ISO8601DateFormatter().string(from: Date())

        // Tactile graphics are declared by the formats actually present, or
        // `none`. Claiming graphics that are not there would mislead a reader
        // deciding whether the file is usable on their device.
        //
        // The spec orders this list most-used to least-used, so it is counted
        // rather than sorted alphabetically. Ties fall back to a fixed order
        // so the same document always produces the same declaration.
        var graphicsCounts: [String: Int] = [:]
        for image in images {
            guard let format = Self.graphicsFormat(for: image.mediaType) else { continue }
            graphicsCounts[format, default: 0] += 1
        }
        let formatRank = ["JPG": 0, "PNG": 1, "SVG": 2, "PDF": 3]
        let graphicsFormats = graphicsCounts.sorted { left, right in
            if left.value != right.value { return left.value > right.value }
            return (formatRank[left.key] ?? .max) < (formatRank[right.key] ?? .max)
        }.map(\.key)
        let tactileGraphics = graphicsFormats.isEmpty
            ? "none"
            : graphicsFormats.joined(separator: ", ")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="\(escape(language))" prefix="a11y: http://www.idpf.org/epub/vocab/package/a11y/# dcterms: http://purl.org/dc/terms/">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="pub-id">\(escape(identifier))</dc:identifier>
        <dc:title>\(escape(translations(title)))</dc:title>
        <dc:creator>\(escape(metadata.effectiveCreator))</dc:creator>
        <dc:language>\(escape(language))</dc:language>
        <dc:format>\(EBrailleMetadata.formatIdentifier)</dc:format>
        <dc:date>\(modified)</dc:date>
        <meta property="dcterms:dateCopyrighted">\(escape(metadata.effectiveCopyrightYear))</meta>
        <meta property="dcterms:modified">\(modified)</meta>
        <meta property="a11y:brailleCellType">\(EBrailleMetadata.cellType)</meta>
        <meta property="a11y:brailleSystem">\(escape(metadata.grade.systemName))</meta>
        <meta property="a11y:completeTranscription">\(metadata.isCompleteTranscription)</meta>
        <meta property="a11y:tactileGraphics">\(escape(tactileGraphics))</meta>
        <meta property="a11y:producer">\(escape(EBrailleMetadata.producer))</meta>
        <!-- The formatting standard the layout follows. eBraille defines no
             property for this, so the Dublin Core term is used; section 5.3.5
             allows additional metadata. Without it, nothing in the file says
             which national layout conventions the cell positions follow. -->
        <meta property="dcterms:conformsTo">\(escape(EBrailleMetadata.formatStandard))</meta>
        <meta property="schema:accessMode">tactile</meta>
        <meta property="schema:accessModeSufficient">tactile</meta>
        <meta property="schema:accessibilityFeature">braille</meta>
        <meta property="schema:accessibilityFeature">structuralNavigation</meta>
        <meta property="schema:accessibilityFeature">tableOfContents</meta>
        <meta property="schema:accessibilityHazard">none</meta>
        <meta property="schema:accessibilitySummary">Braille transcription with semantic headings, lists, and table markup, produced from a markdown source.</meta>
        </metadata>
        <manifest>
        <item id="nav" href="index.html" media-type="application/xhtml+xml" properties="nav"/>
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

    private static func navigationDocument(
        title: String,
        language: String,
        document: ExportDocument,
        translations: TranslationTable
    ) -> String {
        var items: [String] = []
        var counter = 0

        for block in document.blocks {
            guard case .heading(let level, let content) = block, level <= 3 else { continue }
            // Looked up untrimmed: the table is keyed by the exact string
            // that was collected, so trimming here would miss the entry and
            // silently emit an empty nav label.
            let text = content.plainText
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            counter += 1
            items.append(
                "<li><a href=\"content.xhtml#heading-\(counter)\">\(escape(translations(text)))</a></li>"
            )
        }

        if items.isEmpty {
            items.append("<li><a href=\"content.xhtml\">\(escape(translations(title)))</a></li>")
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(escape(language))" lang="\(escape(language))">
        <head>
        <meta charset="utf-8"/>
        <title>\(escape(translations(title)))</title>
        <!-- Required: the primary entry page must point at the package
             document, so a browser opening index.html directly can find the
             rest of the publication. -->
        <link rel="publication" href="package.opf" type="application/oebps-package+xml"/>
        </head>
        <body>
        <nav epub:type="toc" id="toc" role="doc-toc">
        <ol>
        \(items.joined(separator: "\n"))
        </ol>
        </nav>
        </body>
        </html>
        """
    }

    private static func contentDocument(
        title: String,
        language: String,
        document: ExportDocument,
        translations: TranslationTable,
        includeTitleHeading: Bool
    ) -> String {
        var builder = ContentBuilder(translations: translations)
        var body = ""

        if includeTitleHeading {
            builder.headingCounter += 1
            body += "<h1 id=\"heading-\(builder.headingCounter)\">"
                + escape(translations(title)) + "</h1>\n"
        }

        body += builder.render(document.blocks)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(escape(language))" lang="\(escape(language))">
        <head>
        <meta charset="utf-8"/>
        <title>\(escape(translations(title)))</title>
        <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Renders blocks to XHTML carrying braille.
    ///
    /// Structurally close to the EPUB builder, but the inline handling differs
    /// in a way that matters: emphasis and strong carry no braille meaning of
    /// their own here, because UEB expresses emphasis with its own indicators
    /// inside the translated text. The elements are kept for structure, not to
    /// instruct the display.
    private struct ContentBuilder {
        let translations: TranslationTable
        var headingCounter = 0

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

                case .codeBlock(_, let code):
                    // The language class is dropped: it exists for syntax
                    // highlighting, which a braille display has no notion of.
                    output += "<pre>" + escape(translations(code)) + "</pre>\n"

                case .thematicBreak:
                    output += "<hr/>\n"
                }
            }

            return output
        }

        mutating func renderList(_ list: ExportList) -> String {
            let tag = list.isOrdered ? "ol" : "ul"
            var output = "<\(tag)>\n"

            for (offset, item) in list.items.enumerated() {
                output += "<li>"

                // eBraille forbids relying on reading-system generated markers,
                // so the marker is part of the content. Numbers are translated
                // through the braille table rather than written as digits,
                // since braille numerals need their own indicator.
                let marker = list.isOrdered
                    ? "\(list.start + offset)."
                    : "-"
                output += escape(translations(marker)) + Self.brailleSpace

                if let state = item.taskState {
                    output += escape(translations(state.spokenPrefix)) + Self.brailleSpace
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
            // No alignment styling: eBraille leaves presentation to the reading
            // system, and text-align has no meaning on a braille display.
            var output = "<table>\n"

            if !table.headers.isEmpty, !table.headers.allSatisfy(\.isEffectivelyEmpty) {
                output += "<thead>\n<tr>"
                for cell in table.headers {
                    output += "<th scope=\"col\">" + inline(cell) + "</th>"
                }
                output += "</tr>\n</thead>\n"
            }

            if !table.rows.isEmpty {
                output += "<tbody>\n"
                for row in table.rows {
                    output += "<tr>"
                    for cell in row {
                        output += "<td>" + inline(cell) + "</td>"
                    }
                    output += "</tr>"
                    output += "\n"
                }
                output += "</tbody>\n"
            }

            return output + "</table>\n"
        }

        /// The space between a list marker and its text.
        ///
        /// U+2800, not U+0020. Every character in rendered eBraille text comes
        /// from the braille block; an ASCII space is a print character in a
        /// braille document, and a validator will reject it.
        static let brailleSpace = "\u{2800}"

        func inline(_ spans: [ExportInline]) -> String {
            var output = ""

            for span in spans {
                switch span {
                case .text(let value):
                    output += escape(translations(value))
                case .emphasis(let children):
                    output += "<em>" + inline(children) + "</em>"
                case .strong(let children):
                    output += "<strong>" + inline(children) + "</strong>"
                case .strikethrough(let children):
                    output += "<del>" + inline(children) + "</del>"
                case .underline(let children):
                    output += "<u>" + inline(children) + "</u>"
                case .code(let value):
                    output += "<code>" + escape(translations(value)) + "</code>"
                case .link(let destination, let content):
                    // The href stays a real URL — it is machine-readable, not
                    // rendered text, and translating it would break the link.
                    output += "<a href=\"\(escape(destination))\">" + inline(content) + "</a>"
                case .image(let image):
                    output += renderImage(image)
                case .lineBreak:
                    output += "<br/>"
                }
            }

            return output
        }

        func renderImage(_ image: ExportImage) -> String {
            let href = EPUBWriter.imageHref(for: image.source)
            if image.isDecorative {
                return "<img src=\"\(escape(href))\" alt=\"\" role=\"presentation\"/>"
            }
            let alternative = image.alternativeText.map { translations($0) } ?? ""
            return "<img src=\"\(escape(href))\" alt=\"\(escape(alternative))\"/>"
        }
    }

    /// The eBraille name for a core image media type, or nil for anything the
    /// standard does not count as a graphics format.
    private static func graphicsFormat(for mediaType: String) -> String? {
        switch mediaType {
        case "image/jpeg": return "JPG"
        case "image/png": return "PNG"
        case "image/svg+xml": return "SVG"
        case "application/pdf": return "PDF"
        default: return nil
        }
    }

    private static func escape(_ text: String) -> String {
        EPUBWriter.escape(text)
    }
}
