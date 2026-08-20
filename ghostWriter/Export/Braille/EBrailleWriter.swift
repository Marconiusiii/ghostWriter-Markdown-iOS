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
        if let message = metadata.validationMessage {
            throw EBrailleExportError.invalidMetadata(message)
        }
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

        let collectedImages = EPUBWriter.collectImageResources(
            document,
            sourceDirectory: sourceDirectory
        )
        let supportedImages = collectedImages.images.filter {
            $0.mediaType == "image/jpeg" || $0.mediaType == "image/png"
        }
        let supportedHrefs = Set(supportedImages.map(\.href))
        let imageResources = EPUBWriter.ImageResources(
            images: supportedImages,
            hrefBySource: collectedImages.hrefBySource.filter {
                supportedHrefs.contains($0.value)
            }
        )

        entries["package.opf"] = Data(packageDocument(
            title: bookTitle,
            identifier: identifier,
            language: language,
            metadata: metadata,
            images: imageResources.images,
            translations: translations
        ).utf8)

        entries["index.html"] = Data(navigationDocument(
            title: bookTitle,
            language: language,
            document: document,
            translations: translations,
            includeTitleHeading: !startsWithMatchingHeading(document, title: bookTitle)
        ).utf8)

        entries["style.css"] = Data(stylesheet.utf8)

        entries["content.xhtml"] = Data(contentDocument(
            title: bookTitle,
            language: language,
            document: document,
            translations: translations,
            includeTitleHeading: !startsWithMatchingHeading(document, title: bookTitle),
            imageResources: imageResources
        ).utf8)

        for image in imageResources.images {
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
        private var braille: [BrailleTranslationInput: String] = [:]

        enum InlineUnit {
            case text(BrailleTranslationInput)
            case link(destination: String, input: BrailleTranslationInput)
            case image(ExportImage)
            case lineBreak
        }

        mutating func gather(
            from document: ExportDocument,
            title: String,
            grade: BrailleGrade,
            translator: BrailleTranslator
        ) async throws {
            var inputs = Set<BrailleTranslationInput>()
            inputs.insert(BrailleTranslationInput(text: title))
            Self.collect(document.blocks, into: &inputs)

            for input in inputs {
                // Translate the string as it stands, not a trimmed copy.
                // Leading and trailing spaces are word boundaries: a run like
                // "This text is " sits directly against an emphasised run, and
                // trimming the space here joined them into "isbold". liblouis
                // renders a space as U+2800 and preserves it, so the only
                // thing trimming achieved was losing it.
                guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                braille[input] = try await translator.translate(input, grade: grade)
            }
        }

        /// Braille for a print string. Untranslated text never reaches the
        /// output: an empty result is correct for whitespace, and anything
        /// else would be a print string appearing in a braille document.
        func callAsFunction(_ text: String) -> String {
            self(BrailleTranslationInput(text: text))
        }

        func callAsFunction(_ input: BrailleTranslationInput) -> String {
            braille[input] ?? ""
        }

        private static func collect(
            _ blocks: [ExportBlock],
            into inputs: inout Set<BrailleTranslationInput>
        ) {
            for block in blocks {
                switch block {
                case .heading(_, let content):
                    inputs.insert(BrailleTranslationInput(text: content.plainText))
                    collect(inline: content, into: &inputs)
                case .paragraph(let content):
                    collect(inline: content, into: &inputs)
                case .list(let list):
                    for (offset, item) in list.items.enumerated() {
                        let marker = list.isOrdered ? "\(list.start + offset)." : "-"
                        inputs.insert(BrailleTranslationInput(text: marker))
                        if let state = item.taskState {
                            inputs.insert(BrailleTranslationInput(text: state.spokenPrefix))
                        }
                        collect(inline: item.content, into: &inputs)
                        collect(item.children, into: &inputs)
                    }
                case .table(let table):
                    for cell in table.headers { collect(inline: cell, into: &inputs) }
                    for row in table.rows {
                        for cell in row { collect(inline: cell, into: &inputs) }
                    }
                case .blockQuote(let children):
                    collect(children, into: &inputs)
                case .codeBlock(_, let code):
                    inputs.insert(styledInput(code, adding: .noContract))
                case .thematicBreak:
                    continue
                }
            }
        }

        private static func collect(
            inline spans: [ExportInline],
            into inputs: inout Set<BrailleTranslationInput>
        ) {
            for unit in inlineUnits(spans) {
                switch unit {
                case .text(let input), .link(_, let input):
                    inputs.insert(input)
                case .image(let image):
                    if let alternative = image.alternativeText {
                        inputs.insert(BrailleTranslationInput(text: alternative))
                    }
                case .lineBreak:
                    break
                }
            }
        }

        static func inlineUnits(_ spans: [ExportInline]) -> [InlineUnit] {
            var units: [InlineUnit] = []
            var text = ""
            var typeforms: [BrailleTypeform] = []

            func append(_ input: BrailleTranslationInput) {
                text += input.text
                typeforms += input.typeforms
            }

            func flush() {
                guard !text.isEmpty else { return }
                units.append(.text(BrailleTranslationInput(text: text, typeforms: typeforms)))
                text = ""
                typeforms = []
            }

            for span in spans {
                switch span {
                case .link(let destination, let children):
                    flush()
                    units.append(.link(
                        destination: destination,
                        input: flattened(children)
                    ))
                case .image(let image):
                    flush()
                    units.append(.image(image))
                case .lineBreak:
                    flush()
                    units.append(.lineBreak)
                default:
                    append(flattened([span]))
                }
            }
            flush()
            return units
        }

        private static func flattened(
            _ spans: [ExportInline],
            form: BrailleTypeform = []
        ) -> BrailleTranslationInput {
            var text = ""
            var typeforms: [BrailleTypeform] = []

            func append(_ value: String, using typeform: BrailleTypeform) {
                text += value
                typeforms.append(
                    contentsOf: repeatElement(typeform, count: value.utf16.count)
                )
            }

            func visit(_ children: [ExportInline], using typeform: BrailleTypeform) {
                for child in children {
                    switch child {
                    case .text(let value): append(value, using: typeform)
                    case .emphasis(let nested): visit(nested, using: typeform.union(.italic))
                    case .strong(let nested): visit(nested, using: typeform.union(.bold))
                    case .underline(let nested): visit(nested, using: typeform.union(.underline))
                    case .strikethrough(let nested): visit(nested, using: typeform)
                    case .code(let value): append(value, using: typeform.union(.noContract))
                    case .link(_, let nested): visit(nested, using: typeform)
                    case .image(let image): append(image.alternativeText ?? "", using: typeform)
                    case .lineBreak: append("\n", using: typeform)
                    }
                }
            }

            visit(spans, using: form)
            return BrailleTranslationInput(text: text, typeforms: typeforms)
        }

        static func styledInput(
            _ text: String,
            adding form: BrailleTypeform
        ) -> BrailleTranslationInput {
            BrailleTranslationInput(
                text: text,
                typeforms: Array(repeating: form, count: text.utf16.count)
            )
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

    /// Positions are in `ch`, which is the unit eBraille defines for cell
    /// spacing:
    /// eBraille requires a reading system to guarantee that `1ch` is the
    /// cell-to-cell distance and `1em` the line-to-line distance.
    ///
    /// Rendering is still left to the reading system: no font, size, colour,
    /// or decoration is set. The stylesheet supplies only structural spacing.
    ///
    /// The conventional notation below is "start-runover": 3-1 means the first
    /// line begins in cell 3 and continued lines return to cell 1. In CSS that
    /// is a `margin-left` for the runover and a `text-indent` for the
    /// difference on the first line.
    private static let stylesheet = """
    body { margin: 0; }

    /* A simple heading hierarchy that does not constrain font or cell size. */
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

        // Ordinary embedded pictures are not automatically tactile graphics.
        // Markdown has no way to assert that an image was prepared as one, so
        // the export makes the conservative and accurate declaration.
        let tactileGraphics = "none"

        let producers = metadata.effectiveProducers.map { producer in
            "<meta property=\"a11y:producer\">\(escape(producer))</meta>"
        }.joined(separator: "\n")

        // The RECOMMENDED properties. Each is written only when the writer
        // supplied it: an empty `dc:rights` asserts that the rights are known
        // to be nothing, which is worse than the element being absent.
        let recommended = [
            ("dc:source", metadata.source),
            ("dc:publisher", metadata.publisher),
            ("dc:rights", metadata.rights),
            ("dc:subject", metadata.subject),
            ("dc:description", metadata.descriptionText),
        ].compactMap { name, value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "<\(name)>\(escape(trimmed))</\(name)>"
        }
        + [metadata.educationLevel].compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "<meta property=\"dcterms:educationLevel\">\(escape(trimmed))</meta>"
        }

        // Joined with a leading newline so that an empty list leaves no blank
        // line behind in the package document.
        let recommendedBlock = recommended.isEmpty
            ? ""
            : "\n" + recommended.joined(separator: "\n")

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
        <meta property="dcterms:dateCopyrighted">\(escape(metadata.effectiveCopyrightYear ?? ""))</meta>
        <meta property="dcterms:modified">\(modified)</meta>
        <meta property="a11y:brailleCellType">\(EBrailleMetadata.cellType)</meta>
        <meta property="a11y:brailleSystem">\(escape(metadata.grade.systemName))</meta>
        <meta property="a11y:completeTranscription">\(metadata.isCompleteTranscription)</meta>
        <meta property="a11y:tactileGraphics">\(escape(tactileGraphics))</meta>
        \(producers)\(recommendedBlock)
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
        translations: TranslationTable,
        includeTitleHeading: Bool
    ) -> String {
        let headings = document.headings(startingAt: includeTitleHeading ? 2 : 1)
        let items = navigationList(headings, translations: translations)
        let contents = items.isEmpty
            ? "<ol>\n<li><a href=\"content.xhtml\">\(escape(translations(title)))</a></li>\n</ol>"
            : items

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

    private static func navigationList(
        _ headings: [ExportHeading],
        translations: TranslationTable
    ) -> String {
        var roots: [NavigationNode] = []
        var stack: [NavigationNode] = []
        for heading in headings {
            while let last = stack.last, last.heading.level >= heading.level {
                stack.removeLast()
            }
            let node = NavigationNode(heading)
            if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }
            stack.append(node)
        }

        func render(_ nodes: [NavigationNode]) -> String {
            guard !nodes.isEmpty else { return "" }
            let items = nodes.map { node in
                let label = translations(BrailleTranslationInput(text: node.heading.content.plainText))
                return "<li><a href=\"content.xhtml#\(node.heading.identifier)\">\(escape(label))</a>\(render(node.children))</li>"
            }.joined(separator: "\n")
            return "<ol>\n\(items)\n</ol>"
        }
        return render(roots)
    }

    private static func contentDocument(
        title: String,
        language: String,
        document: ExportDocument,
        translations: TranslationTable,
        includeTitleHeading: Bool,
        imageResources: EPUBWriter.ImageResources
    ) -> String {
        var builder = ContentBuilder(
            translations: translations,
            imageResources: imageResources
        )
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
        let imageResources: EPUBWriter.ImageResources
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
                    let input = TranslationTable.styledInput(code, adding: .noContract)
                    output += "<pre>" + escape(translations(input)) + "</pre>\n"

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

            for unit in TranslationTable.inlineUnits(spans) {
                switch unit {
                case .text(let input):
                    output += escape(translations(input))
                case .link(let destination, let input):
                    // The href stays a real URL — it is machine-readable, not
                    // rendered text, and translating it would break the link.
                    let label = escape(translations(input))
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
                guard !image.isDecorative,
                      let alternative = image.alternativeText else { return "" }
                return "<span class=\"image-description\">\(escape(translations(alternative)))</span>"
            }
            if image.isDecorative { return "<img src=\"\(escape(href))\" alt=\"\"/>" }
            let alternative = image.alternativeText.map { translations($0) } ?? ""
            return "<img src=\"\(escape(href))\" alt=\"\(escape(alternative))\"/>"
        }
    }

    private static func escape(_ text: String) -> String {
        EPUBWriter.escape(text)
    }
}

nonisolated enum EBrailleExportError: LocalizedError, Equatable, Sendable {
    case invalidMetadata(String)

    var errorDescription: String? {
        switch self {
        case .invalidMetadata(let message): return message
        }
    }
}
