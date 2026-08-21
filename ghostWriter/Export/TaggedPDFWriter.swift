//
//  TaggedPDFWriter.swift
//  ghostWriter
//
//  Writes a tagged PDF — one carrying a real structure tree, so a screen reader
//  can navigate it by heading, read a table cell by cell, and announce an
//  image's alternative text.
//
//  This deliberately does not use UIGraphicsPDFRenderer's convenience drawing,
//  nor WKWebView's PDF output. Both produce a picture of text: the glyphs are
//  there, the structure is not, and the result is a document VoiceOver reads as
//  one undifferentiated run. Instead every drawing operation here is wrapped in
//  CGContext's PDF tagging calls, so the marked content in the page stream is
//  bound to a structure element that says what it is.
//
//  Layout is done by hand for the same reason: a PDF page is a fixed rectangle
//  with no reflow, so line breaking, page breaking, and column widths all have
//  to be computed before anything is drawn.
//

import CoreGraphics
import CoreText
import ImageIO
import Foundation
import UIKit

nonisolated enum TaggedPDFWriter {

    // MARK: - Page geometry

    /// US Letter at 72 points per inch, with one-inch margins. Letter rather
    /// than A4 because the app's primary audience is US-based; the margin is
    /// generous enough that the text column stays within a comfortable reading
    /// measure.
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin = CGFloat(72)

    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private static var contentTop: CGFloat { pageSize.height - margin }
    private static var contentBottom: CGFloat { margin }

    // MARK: - Entry point

    static func write(
        title: String,
        markdown: String,
        sourceDirectory: URL? = nil,
        documentLanguage: String = DocumentLanguage.resolvedTag("")
    ) throws -> Data {
        let document = MarkdownDocumentParser.parse(markdown)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw PDFExportError.couldNotCreateDocument
        }

        // A PDF without a title falls back to its file name in assistive
        // technology, and a document-properties title is also what a reader
        // announces when the file opens — so it is set even when the body
        // supplies its own heading.
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let auxiliary: [CFString: Any] = [
            kCGPDFContextTitle: trimmedTitle.isEmpty ? "Document" : trimmedTitle,
            kCGPDFContextCreator: "ghostWriter"
        ]

        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            auxiliary as CFDictionary
        ) else {
            throw PDFExportError.couldNotCreateDocument
        }

        var state = RenderState(
            context: context,
            sourceDirectory: sourceDirectory
        )

        context.beginPDFPage(pageAttributes())
        state.pageIsOpen = true
        state.cursor = contentTop

        // Everything hangs off one Document element spanning every page, which
        // is what makes the file a single continuous reading order rather than
        // a sequence of unrelated pages.
        //
        // The language is not set here. CGPDFContext accepts a languageText
        // property and then discards it, so it is written into the catalog
        // after the file is closed — see PDFLanguageTag.
        tagged(.document, state: &state) { state in
            // A leading title heading gives the document an H1 even when the
            // body does not open with one, which is what a screen reader's
            // heading navigation lands on first.
            if !trimmedTitle.isEmpty, !startsWithMatchingHeading(document, title: trimmedTitle) {
                drawHeading(
                    level: 1,
                    content: [.text(trimmedTitle)],
                    state: &state
                )
            }

            draw(document.blocks, state: &state)
        }

        if state.pageIsOpen {
            context.endPDFPage()
        }
        context.closePDF()

        guard data.length > 0 else {
            throw PDFExportError.couldNotCreateDocument
        }

        let completedStructure = PDFStructureFinalizer.finalizing(
            data as Data,
            figureAlternativeTexts: state.figureAlternativeTexts,
            actualTexts: state.actualTexts
        )

        // CGPDFContext writes no language attribute, and a tagged PDF without
        // one fails an accessibility audit, so it is added to the finished file.
        return PDFLanguageTag.adding(
            language: documentLanguage,
            to: completedStructure
        )
    }

    private static func startsWithMatchingHeading(
        _ document: ExportDocument,
        title: String
    ) -> Bool {
        guard case .heading(1, let content)? = document.blocks.first else { return false }
        return content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(title) == .orderedSame
    }

    private static func pageAttributes() -> CFDictionary {
        // The media box is repeated per page; beginPDFPage takes it even though
        // the context already carries a default.
        let box = CGRect(origin: .zero, size: pageSize)
        return [
            kCGPDFContextMediaBox: NSValue(cgRect: box)
        ] as CFDictionary
    }

    // MARK: - Render state

    /// Tracks where on the page the next block goes, and how deep the tag tree
    /// currently is.
    private struct RenderState {
        struct ActiveTag {
            let type: CGPDFTagType
            let properties: [CGPDFTagProperty: String]
        }

        let context: CGContext
        let sourceDirectory: URL?
        var cursor: CGFloat = 0
        var pageIsOpen = false
        /// Left edge of the current text column. Lists and quotes shift it.
        var leftInset: CGFloat = 0
        var activeTags: [ActiveTag] = []
        var figureAlternativeTexts: [String] = []
        var actualTexts: [String] = []

        var availableWidth: CGFloat {
            contentWidth - leftInset
        }

        var originX: CGFloat {
            margin + leftInset
        }

        var remainingHeight: CGFloat {
            cursor - contentBottom
        }
    }

    /// Ends the current page and starts a new one.
    ///
    /// PDF structure elements cannot remain open while a page is ended. Close
    /// the active hierarchy before the break and reopen the same hierarchy on
    /// the new page so every page has a valid marked-content relationship.
    private static func newPage(_ state: inout RenderState) {
        if state.pageIsOpen {
            for _ in state.activeTags.reversed() {
                CGPDFContextEndTag(state.context)
            }
            state.context.endPDFPage()
        }
        state.context.beginPDFPage(pageAttributes())
        for tag in state.activeTags {
            CGPDFContextBeginTag(
                state.context,
                tag.type,
                tag.properties as CFDictionary
            )
        }
        state.pageIsOpen = true
        state.cursor = contentTop
    }

    private static func ensureSpace(_ needed: CGFloat, state: inout RenderState) {
        if state.remainingHeight < needed {
            newPage(&state)
        }
    }

    // MARK: - Tagging

    /// Opens a structure element, runs `body`, and closes it.
    ///
    /// Every drawing operation must sit inside a tag. Anything drawn outside
    /// one becomes untagged content, which conforming readers either skip or
    /// announce with no context — either way the reader loses it.
    private static func tagged(
        _ tag: CGPDFTagType,
        properties: [CGPDFTagProperty: String] = [:],
        state: inout RenderState,
        body: (inout RenderState) -> Void
    ) {
        // The C function takes a nullable dictionary, but Swift imports the
        // parameter as non-optional, so an empty dictionary stands in for "no
        // properties" — it produces the same tag with no extra attributes.
        CGPDFContextBeginTag(state.context, tag, properties as CFDictionary)
        state.activeTags.append(RenderState.ActiveTag(type: tag, properties: properties))
        body(&state)
        state.activeTags.removeLast()
        CGPDFContextEndTag(state.context)
    }

    /// The tag used for purely visual marks — rules, table borders, the bar
    /// beside a quotation.
    ///
    /// PDF's own term for this is an artifact, but CGPDFTagType exposes no
    /// artifact case. NonStructure is the closest available: it declares an
    /// element that carries no meaning and should be skipped when the document
    /// is read as structure, which is exactly the intent.
    private static let decorationTag = CGPDFTagType.nonStructure

    // MARK: - Block dispatch

    private static func draw(_ blocks: [ExportBlock], state: inout RenderState) {
        for block in blocks {
            switch block {
            case .heading(let level, let content):
                drawHeading(level: level, content: content, state: &state)

            case .paragraph(let content):
                // A paragraph holding nothing but images is the markdown idiom
                // for a figure, so it becomes real Figure elements rather than
                // a paragraph of placeholder text.
                let images = standaloneImages(in: content)
                if !images.isEmpty {
                    for image in images {
                        drawFigure(image, state: &state)
                    }
                    continue
                }
                guard !content.isEffectivelyEmpty else { continue }
                drawParagraph(content, tag: .paragraph, state: &state)

            case .list(let list):
                drawList(list, state: &state)

            case .table(let table):
                drawTable(table, state: &state)

            case .blockQuote(let children):
                drawBlockQuote(children, state: &state)

            case .codeBlock(let language, let code):
                drawCodeBlock(language: language, code: code, state: &state)

            case .thematicBreak:
                drawThematicBreak(state: &state)
            }
        }
    }

    // MARK: - Figures

    /// Returns the images in a paragraph that consists only of images and
    /// whitespace. A paragraph mixing images with prose is left alone, because
    /// there the image belongs inside the sentence.
    private static func standaloneImages(in content: [ExportInline]) -> [ExportImage] {
        var images: [ExportImage] = []

        for span in content {
            switch span {
            case .image(let image):
                images.append(image)
            case .text(let value):
                guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return []
                }
            case .lineBreak:
                continue
            default:
                return []
            }
        }

        return images
    }

    /// Draws an image as a Figure element carrying its alternative text.
    ///
    /// The alt text is what a screen reader announces in place of the picture,
    /// so it is attached as a tag property rather than drawn on the page. An
    /// image with empty alt text is decorative by markdown convention: it is
    /// drawn, but tagged as decoration so it is passed over silently instead of
    /// being announced as an unlabelled graphic.
    private static func drawFigure(_ image: ExportImage, state: inout RenderState) {
        let metrics = PDFTextLayout.metrics

        guard let loaded = loadImage(image, sourceDirectory: state.sourceDirectory) else {
            // An image that cannot be found still has to be accounted for —
            // silently dropping it would leave the reader unaware that the
            // document referred to a picture at all.
            guard let alt = image.alternativeText, !alt.isEmpty else { return }
            var style = PDFTextLayout.InlineStyle(size: metrics.body)
            style.italic = true
            style.color = PDFPalette.secondary
            drawParagraph(
                [.text("[Image not available: \(alt)]")],
                tag: .caption,
                state: &state,
                style: style
            )
            return
        }

        // Scale to fit the column, never up — enlarging a small image past its
        // natural size only makes it blurrier.
        let pixelWidth = CGFloat(loaded.width)
        let pixelHeight = CGFloat(loaded.height)
        guard pixelWidth > 0, pixelHeight > 0 else { return }

        let scale = min(1, state.availableWidth / pixelWidth)
        var drawWidth = pixelWidth * scale
        var drawHeight = pixelHeight * scale

        // An image taller than the text column would never fit on any page, so
        // it is bounded by the page height as well.
        let maximumHeight = contentTop - contentBottom
        if drawHeight > maximumHeight {
            let shrink = maximumHeight / drawHeight
            drawWidth *= shrink
            drawHeight *= shrink
        }

        state.cursor -= metrics.paragraphSpacing / 2
        ensureSpace(drawHeight, state: &state)

        let properties: [CGPDFTagProperty: String] = image.isDecorative
            ? [:]
            : [.alternativeText: image.alternativeText ?? ""]
        if !image.isDecorative {
            state.figureAlternativeTexts.append(image.alternativeText ?? "")
        }

        tagged(
            image.isDecorative ? decorationTag : .figure,
            properties: properties,
            state: &state
        ) { state in
            let rect = CGRect(
                x: state.originX,
                y: state.cursor - drawHeight,
                width: drawWidth,
                height: drawHeight
            )
            state.context.draw(loaded, in: rect)
        }

        state.cursor -= drawHeight + metrics.paragraphSpacing
    }

    /// Loads a local image referenced by the markdown. Remote sources are not
    /// fetched: an export must not depend on the network, and a half-downloaded
    /// document is worse than one that says the image was unavailable.
    private static func loadImage(
        _ image: ExportImage,
        sourceDirectory: URL?
    ) -> CGImage? {
        guard let sourceDirectory else { return nil }
        let decoded = image.source.removingPercentEncoding ?? image.source
        guard !decoded.hasPrefix("/"), URL(string: decoded)?.scheme == nil else { return nil }
        let relativeComponents = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard let assetDirectory = relativeComponents.first,
              assetDirectory.hasPrefix(".ghostwriter-assets-") else { return nil }
        let root = sourceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(decoded).standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPrefix) else { return nil }

        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }

        guard let decodedImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return normalizedImageForPDF(decodedImage)
    }

    /// Quartz PDF output can produce an invalid image colour-space dictionary
    /// for otherwise decodable indexed or grayscale-plus-alpha images. Drawing
    /// through a standard sRGB bitmap first gives every embedded image a stable
    /// eight-bit RGB representation that PDF readers agree on.
    private static func normalizedImageForPDF(_ image: CGImage) -> CGImage? {
        guard image.width > 0, image.height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return context.makeImage()
    }

    // MARK: - Headings

    private static func drawHeading(
        level: Int,
        content: [ExportInline],
        state: inout RenderState
    ) {
        guard !content.isEffectivelyEmpty else { return }

        let metrics = PDFTextLayout.metrics
        let style = PDFTextLayout.InlineStyle(
            size: metrics.headingSize(level: level),
            bold: true
        )
        let attributed = PDFTextLayout.attributedString(for: content, style: style)
        let lines = PDFTextLayout.lines(for: attributed, width: state.availableWidth)

        state.cursor -= metrics.headingSpacingBefore(level: level)

        // Keep a heading with at least the first line of what follows. A
        // heading stranded at the foot of a page reads as though its section
        // were empty.
        let needed = PDFTextLayout.height(of: lines) + metrics.body * 2
        ensureSpace(needed, state: &state)

        tagged(headingTag(level: level), state: &state) { state in
            drawLines(lines, attributed: attributed, state: &state)
        }

        state.cursor -= metrics.paragraphSpacing / 2
    }

    /// Maps a markdown heading level to its PDF tag. Levels beyond six are
    /// clamped, because the format defines no deeper heading and an unknown tag
    /// would strip the semantics entirely.
    private static func headingTag(level: Int) -> CGPDFTagType {
        switch level {
        case 1: return .header1
        case 2: return .header2
        case 3: return .header3
        case 4: return .header4
        case 5: return .header5
        default: return .header6
        }
    }

    // MARK: - Paragraphs

    private static func drawParagraph(
        _ content: [ExportInline],
        tag: CGPDFTagType,
        state: inout RenderState,
        style overrideStyle: PDFTextLayout.InlineStyle? = nil,
        spacingAfter: CGFloat? = nil
    ) {
        let metrics = PDFTextLayout.metrics
        let style = overrideStyle ?? PDFTextLayout.InlineStyle(size: metrics.body)
        let attributed = PDFTextLayout.attributedString(for: content, style: style)
        let lines = PDFTextLayout.lines(for: attributed, width: state.availableWidth)
        guard !lines.isEmpty else { return }

        tagged(tag, state: &state) { state in
            drawLines(lines, attributed: attributed, state: &state)
        }

        state.cursor -= spacingAfter ?? metrics.paragraphSpacing
    }

    /// Draws laid-out lines, breaking pages as needed.
    ///
    /// Link annotations are added per line rather than per paragraph, because a
    /// link that wraps produces two separate rectangles and a single annotation
    /// spanning both would cover unrelated text.
    private static func drawLines(
        _ lines: [PDFTextLayout.Line],
        attributed: NSAttributedString,
        state: inout RenderState,
        alignment: ExportAlignment = .natural
    ) {
        let context = state.context

        for line in lines {
            if state.remainingHeight < line.height {
                newPage(&state)
            }

            state.cursor -= line.ascent

            let x = state.originX + PDFTextLayout.offset(
                for: line,
                in: state.availableWidth,
                alignment: alignment
            )

            let spokenText = attributed.attributedSubstring(from: line.range).string
            state.actualTexts.append(spokenText)
            tagged(
                .span,
                properties: [.actualText: spokenText],
                state: &state
            ) { state in
                drawLineContent(
                    line,
                    attributed: attributed,
                    originX: x,
                    baseline: state.cursor,
                    state: &state
                )
            }

            addLinkAnnotations(
                for: line,
                attributed: attributed,
                originX: x,
                baseline: state.cursor,
                context: context
            )

            state.cursor -= line.descent + line.leading
        }
    }

    /// Draws link text inside Link structure elements while leaving ordinary
    /// text in its surrounding paragraph, heading, list body, or table cell.
    /// The link annotation is added separately below; both pieces are needed
    /// for a link to be discoverable and actionable in a tagged PDF.
    private static func drawLineContent(
        _ line: PDFTextLayout.Line,
        attributed: NSAttributedString,
        originX: CGFloat,
        baseline: CGFloat,
        state: inout RenderState
    ) {
        guard line.range.length > 0,
              line.range.upperBound <= attributed.length else { return }

        var linkRanges: [NSRange] = []
        attributed.enumerateAttribute(.link, in: line.range) { value, range, _ in
            if linkURL(from: value) != nil { linkRanges.append(range) }
        }

        guard !linkRanges.isEmpty else {
            state.context.textPosition = CGPoint(x: originX, y: baseline)
            CTLineDraw(line.ctLine, state.context)
            return
        }

        var cursor = line.range.location
        for linkRange in linkRanges {
            if cursor < linkRange.location {
                drawLineFragment(
                    NSRange(location: cursor, length: linkRange.location - cursor),
                    line: line,
                    attributed: attributed,
                    originX: originX,
                    baseline: baseline,
                    context: state.context
                )
            }
            tagged(.link, state: &state) { state in
                drawLineFragment(
                    linkRange,
                    line: line,
                    attributed: attributed,
                    originX: originX,
                    baseline: baseline,
                    context: state.context
                )
            }
            cursor = linkRange.upperBound
        }

        if cursor < line.range.upperBound {
            drawLineFragment(
                NSRange(location: cursor, length: line.range.upperBound - cursor),
                line: line,
                attributed: attributed,
                originX: originX,
                baseline: baseline,
                context: state.context
            )
        }
    }

    private static func drawLineFragment(
        _ range: NSRange,
        line: PDFTextLayout.Line,
        attributed: NSAttributedString,
        originX: CGFloat,
        baseline: CGFloat,
        context: CGContext
    ) {
        guard range.length > 0 else { return }
        let fragment = attributed.attributedSubstring(from: range)
        let fragmentLine = CTLineCreateWithAttributedString(fragment)
        let offset = CTLineGetOffsetForStringIndex(line.ctLine, range.location, nil)
        context.textPosition = CGPoint(x: originX + offset, y: baseline)
        CTLineDraw(fragmentLine, context)
    }

    /// Emits a real PDF link annotation for any link attribute on this line, so
    /// the URL is followable rather than merely visible.
    private static func addLinkAnnotations(
        for line: PDFTextLayout.Line,
        attributed: NSAttributedString,
        originX: CGFloat,
        baseline: CGFloat,
        context: CGContext
    ) {
        guard line.range.length > 0, line.range.upperBound <= attributed.length else { return }

        attributed.enumerateAttribute(
            .link,
            in: line.range,
            options: []
        ) { value, range, _ in
            guard let destination = linkURL(from: value) else { return }

            let startOffset = CTLineGetOffsetForStringIndex(line.ctLine, range.location, nil)
            let endOffset = CTLineGetOffsetForStringIndex(
                line.ctLine,
                range.location + range.length,
                nil
            )

            let rect = CGRect(
                x: originX + min(startOffset, endOffset),
                y: baseline - line.descent,
                width: abs(endOffset - startOffset),
                height: line.ascent + line.descent
            )
            guard rect.width > 0 else { return }

            context.setURL(destination as CFURL, for: rect)
        }
    }

    private static func linkURL(from value: Any?) -> URL? {
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }

    // MARK: - Lists

    private static func drawList(_ list: ExportList, state: inout RenderState) {
        let metrics = PDFTextLayout.metrics
        // Room for "10." at body size, so two-digit lists do not collide with
        // their text.
        let markerWidth = CGFloat(22)
        var number = list.start

        tagged(.list, state: &state) { state in
            for item in list.items {
                let marker = list.isOrdered ? "\(number)." : "•"
                number += 1

                tagged(.listItem, state: &state) { state in
                    drawListItem(
                        item,
                        marker: marker,
                        markerWidth: markerWidth,
                        state: &state
                    )
                }
            }
        }

        state.cursor -= metrics.paragraphSpacing / 2
    }

    private static func drawListItem(
        _ item: ExportListItem,
        marker: String,
        markerWidth: CGFloat,
        state: inout RenderState
    ) {
        let metrics = PDFTextLayout.metrics
        let style = PDFTextLayout.InlineStyle(size: metrics.body)

        // The item's own text, indented to leave room for the marker.
        var content = item.content
        if let task = item.taskState {
            // A checkbox glyph is either silent or read as a symbol name, so
            // the state is stated in words. This matches how the HTML and Word
            // exports handle task lists.
            content.insert(.text(task.spokenPrefix + " "), at: 0)
        }

        let attributed = PDFTextLayout.attributedString(for: content, style: style)
        let textInset = state.leftInset + markerWidth
        let lines = PDFTextLayout.lines(
            for: attributed,
            width: contentWidth - textInset
        )

        let firstLineHeight = lines.first?.height ?? metrics.body * 1.4
        ensureSpace(firstLineHeight, state: &state)

        // The marker is tagged as a label, which keeps it out of the item's
        // text but still in the reading order — a reader that announces list
        // position uses it, and one that does not simply skips it.
        let markerBaseline = state.cursor - (lines.first?.ascent ?? metrics.body)
        tagged(.label, state: &state) { state in
            let markerString = NSAttributedString(
                string: marker,
                attributes: [
                    .font: UIFont.systemFont(ofSize: metrics.body),
                    .foregroundColor: PDFPalette.text
                ]
            )
            let markerLine = CTLineCreateWithAttributedString(markerString)
            state.context.textPosition = CGPoint(
                x: margin + state.leftInset,
                y: markerBaseline
            )
            CTLineDraw(markerLine, state.context)
        }

        let outerInset = state.leftInset
        state.leftInset = textInset

        if !lines.isEmpty {
            tagged(.listBody, state: &state) { state in
                drawLines(lines, attributed: attributed, state: &state)
            }
        }

        // Nested content sits inside the same list item element, so its
        // containment in the structure tree matches its visual indentation.
        if !item.children.isEmpty {
            state.cursor -= metrics.lineSpacing
            draw(item.children, state: &state)
        } else {
            state.cursor -= metrics.lineSpacing
        }

        state.leftInset = outerInset
    }

    // MARK: - Block quotes

    private static func drawBlockQuote(_ children: [ExportBlock], state: inout RenderState) {
        let metrics = PDFTextLayout.metrics
        let indent = CGFloat(18)

        state.cursor -= metrics.paragraphSpacing / 2

        let outerInset = state.leftInset
        let startCursor = state.cursor

        state.leftInset = outerInset + indent

        tagged(.blockQuote, state: &state) { state in
            draw(children, state: &state)
        }

        // The vertical rule is drawn after the text, once the quote's extent on
        // this page is known. It is decoration, so it sits inside an artifact
        // tag and is never announced.
        tagged(decorationTag, state: &state) { state in
            let top = min(startCursor, contentTop)
            let bottom = max(state.cursor, contentBottom)
            if top > bottom {
                state.context.setStrokeColor(PDFPalette.quoteBar.cgColor)
                state.context.setLineWidth(2)
                state.context.move(to: CGPoint(x: margin + outerInset + 4, y: top))
                state.context.addLine(to: CGPoint(x: margin + outerInset + 4, y: bottom))
                state.context.strokePath()
            }
        }

        state.leftInset = outerInset
    }

    // MARK: - Code blocks

    private static func drawCodeBlock(
        language: String?,
        code: String,
        state: inout RenderState
    ) {
        let metrics = PDFTextLayout.metrics
        let padding = CGFloat(8)

        var style = PDFTextLayout.InlineStyle(size: metrics.code)
        style.monospaced = true
        style.color = PDFPalette.secondary

        // Code is laid out one source line at a time. Long source lines wrap
        // visually instead of being clipped; the underlying text remains one
        // continuous source line because no newline is inserted into it.
        let sourceLines = code.components(separatedBy: "\n")

        state.cursor -= metrics.paragraphSpacing / 2
        ensureSpace(metrics.code * 3, state: &state)

        // A language, when given, is announced before the code so a listener
        // knows what they are about to hear read out character by character.
        if let language, !language.isEmpty {
            var labelStyle = PDFTextLayout.InlineStyle(size: metrics.code)
            labelStyle.italic = true
            labelStyle.color = PDFPalette.secondary
            drawParagraph(
                [.text("Code, \(language):")],
                tag: .caption,
                state: &state,
                style: labelStyle,
                spacingAfter: metrics.lineSpacing
            )
        }

        tagged(.code, state: &state) { state in
            for source in sourceLines {
                let attributed = NSAttributedString(
                    string: source.isEmpty ? " " : source,
                    attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: metrics.code, weight: .regular),
                        .foregroundColor: PDFPalette.secondary
                    ]
                )
                let lines = PDFTextLayout.lines(
                    for: attributed,
                    width: max(state.availableWidth - padding * 2, 40)
                )
                guard !lines.isEmpty else { continue }

                state.leftInset += padding
                drawLines(
                    lines,
                    attributed: attributed,
                    state: &state
                )
                state.leftInset -= padding
            }
        }

        state.cursor -= metrics.paragraphSpacing
    }

    // MARK: - Thematic break

    private static func drawThematicBreak(state: inout RenderState) {
        let metrics = PDFTextLayout.metrics
        state.cursor -= metrics.paragraphSpacing
        ensureSpace(metrics.paragraphSpacing * 2, state: &state)

        // A horizontal rule is purely visual, so it is an artifact. Announcing
        // "line" at every section break would be noise.
        tagged(decorationTag, state: &state) { state in
            state.context.setStrokeColor(PDFPalette.rule.cgColor)
            state.context.setLineWidth(0.5)
            state.context.move(to: CGPoint(x: margin, y: state.cursor))
            state.context.addLine(to: CGPoint(x: pageSize.width - margin, y: state.cursor))
            state.context.strokePath()
        }

        state.cursor -= metrics.paragraphSpacing
    }

    // MARK: - Tables

    private static func drawTable(_ table: ExportTable, state: inout RenderState) {
        let metrics = PDFTextLayout.metrics
        let columnCount = table.columnCount
        guard columnCount > 0 else { return }

        let widths = columnWidths(for: table, totalWidth: state.availableWidth)
        let cellPadding = CGFloat(5)

        state.cursor -= metrics.paragraphSpacing / 2

        tagged(.table, state: &state) { state in
            // Header rows are grouped in a TableHeader element and body rows in
            // a TableBody. The grouping is what tells a reader which row holds
            // the column labels, so a data cell can be announced with its
            // header rather than as a bare value.
            if !table.headers.isEmpty, !table.headers.allSatisfy(\.isEffectivelyEmpty) {
                tagged(.tableHeader, state: &state) { state in
                    drawTableRow(
                        cells: table.headers,
                        table: table,
                        widths: widths,
                        padding: cellPadding,
                        isHeader: true,
                        state: &state
                    )
                }
            }

            if !table.rows.isEmpty {
                tagged(.tableBody, state: &state) { state in
                    for row in table.rows {
                        drawTableRow(
                            cells: row,
                            table: table,
                            widths: widths,
                            padding: cellPadding,
                            isHeader: false,
                            state: &state
                        )
                    }
                }
            }
        }

        state.cursor -= metrics.paragraphSpacing
    }

    private static func drawTableRow(
        cells: [[ExportInline]],
        table: ExportTable,
        widths: [CGFloat],
        padding: CGFloat,
        isHeader: Bool,
        state: inout RenderState
    ) {
        let metrics = PDFTextLayout.metrics
        let columnCount = widths.count

        var style = PDFTextLayout.InlineStyle(size: metrics.body)
        style.bold = isHeader

        // Every cell is laid out before anything is drawn, because the row's
        // height is the tallest cell and a row must not be split across pages —
        // half a row on each side of a break destroys the correspondence
        // between a cell and its column header.
        var laidOut: [(attributed: NSAttributedString, lines: [PDFTextLayout.Line])] = []
        for column in 0..<columnCount {
            let content = column < cells.count ? cells[column] : []
            let attributed = PDFTextLayout.attributedString(for: content, style: style)
            let lines = PDFTextLayout.lines(
                for: attributed,
                width: max(widths[column] - padding * 2, 20)
            )
            laidOut.append((attributed, lines))
        }

        let rowHeight = laidOut.map { PDFTextLayout.height(of: $0.lines) }.max() ?? metrics.body
        let totalHeight = rowHeight + padding * 2

        ensureSpace(totalHeight, state: &state)

        let rowTop = state.cursor
        let context = state.context

        tagged(.tableRow, state: &state) { state in
            var x = state.originX

            for column in 0..<columnCount {
                let (_, lines) = laidOut[column]
                let alignment = table.alignment(forColumn: column)

                // A header cell is tagged TableHeaderCell rather than
                // TableDataCell, which is what lets a reader associate a value
                // with the column it belongs to. PDF's Scope attribute would
                // state the association explicitly, but CGPDFTagProperty
                // exposes only ActualText, AlternativeText, Title, and
                // Language — so the cell tag plus the TableHeader grouping
                // below carry it instead.
                tagged(
                    isHeader ? .tableHeaderCell : .tableDataCell,
                    state: &state
                ) { state in
                    var cellCursor = rowTop - padding

                    for line in lines {
                        cellCursor -= line.ascent
                        let offset = PDFTextLayout.offset(
                            for: line,
                            in: widths[column] - padding * 2,
                            alignment: alignment
                        )
                        context.textPosition = CGPoint(
                            x: x + padding + offset,
                            y: cellCursor
                        )
                        CTLineDraw(line.ctLine, context)
                        cellCursor -= line.descent + line.leading
                    }
                }

                x += widths[column]
            }
        }

        state.cursor = rowTop - totalHeight

        // Rules are decoration only; the structure tree already carries the
        // grid, so drawing them inside an artifact keeps them silent.
        tagged(decorationTag, state: &state) { state in
            context.setStrokeColor(PDFPalette.tableRule.cgColor)
            context.setLineWidth(isHeader ? 0.9 : 0.4)
            context.move(to: CGPoint(x: state.originX, y: state.cursor))
            context.addLine(to: CGPoint(
                x: state.originX + widths.reduce(0, +),
                y: state.cursor
            ))
            context.strokePath()
        }
    }

    /// Distributes width across columns in proportion to how much text each
    /// holds, with a floor so a narrow column stays readable. Equal columns
    /// would leave a column of one-word values as wide as a column of prose.
    private static func columnWidths(
        for table: ExportTable,
        totalWidth: CGFloat
    ) -> [CGFloat] {
        let columnCount = table.columnCount
        guard columnCount > 0 else { return [] }

        var demands = [CGFloat](repeating: 0, count: columnCount)

        func measure(_ cells: [[ExportInline]]) {
            for column in 0..<min(columnCount, cells.count) {
                let length = CGFloat(cells[column].plainText.count)
                demands[column] = max(demands[column], length)
            }
        }

        measure(table.headers)
        for row in table.rows { measure(row) }

        let minimum = max(totalWidth / CGFloat(columnCount) * 0.4, 44)
        let total = demands.reduce(0, +)

        guard total > 0 else {
            return [CGFloat](repeating: totalWidth / CGFloat(columnCount), count: columnCount)
        }

        var widths = demands.map { max(minimum, totalWidth * ($0 / total)) }

        // Proportional shares plus a minimum can exceed the page, so rescale
        // back down to the available width.
        let sum = widths.reduce(0, +)
        if sum > totalWidth {
            let scale = totalWidth / sum
            widths = widths.map { $0 * scale }
        }

        return widths
    }
}

nonisolated enum PDFExportError: LocalizedError, Equatable, Sendable {
    case couldNotCreateDocument

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDocument:
            return String(localized: "The PDF could not be created.")
        }
    }
}
