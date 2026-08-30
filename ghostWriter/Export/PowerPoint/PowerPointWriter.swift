//
//  PowerPointWriter.swift
//  ghostWriter
//
//  Converts the shared semantic Markdown model into a native PresentationML
//  deck. Level 2 headings divide slides; the first top-level thematic break in
//  a slide divides visible content from that slide's speaker notes.
//

import Foundation
import ImageIO

nonisolated enum PowerPointWriter {
    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    private static let slideWidth = 12_192_000
    private static let slideHeight = 6_858_000
    private static let notesWidth = 6_858_000
    private static let notesHeight = 9_144_000

    private struct Deck {
        var title: String
        var titleContent: [ExportBlock]
        var titleNotes: [ExportBlock]
        var slides: [Slide]
    }

    private struct Slide {
        var title: [ExportInline]
        var content: [ExportBlock]
        var notes: [ExportBlock]
    }

    private struct TextRun {
        var text: String
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var code = false
        var hyperlink: String?
    }

    private struct Paragraph {
        enum Marker {
            case none
            case bullet
            case numbered(start: Int?)
        }

        var runs: [TextRun]
        var level = 0
        var marker: Marker = .none
        var fontSize = 2400
        var color = "dk1"
        var bold = false
        var code = false

        var markerIsNone: Bool {
            if case .none = marker { return true }
            return false
        }
    }

    private struct Relationship {
        var id: String
        var type: String
        var target: String
        var external = false
    }

    private struct MediaPart {
        var fileName: String
        var data: Data
        var mediaType: String
    }

    private struct PreparedImage {
        var image: ExportImage
        var data: Data
        var mediaType: String
        var fileExtension: String
        var ratio: Double
    }

    private struct SlideContext {
        var relationships: [Relationship] = []
        var media: [MediaPart] = []
        var nextRelationship = 10

        mutating func addHyperlink(_ target: String) -> String {
            let id = "rId\(nextRelationship)"
            nextRelationship += 1
            relationships.append(Relationship(
                id: id,
                type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
                target: target,
                external: true
            ))
            return id
        }

        mutating func addImage(
            _ image: PreparedImage,
            mediaNumber: Int
        ) -> (id: String, part: MediaPart, ratio: Double) {
            let part = MediaPart(
                fileName: "image\(mediaNumber).\(image.fileExtension)",
                data: image.data,
                mediaType: image.mediaType
            )
            let id = "rId\(nextRelationship)"
            nextRelationship += 1
            relationships.append(Relationship(
                id: id,
                type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
                target: "../media/\(part.fileName)"
            ))
            media.append(part)
            return (id, part, image.ratio)
        }
    }

    static func write(
        title: String,
        markdown: String,
        theme: PowerPointTheme = .warmPaper,
        sourceDirectory: URL? = nil,
        documentLanguage: String = DocumentLanguage.resolvedTag("")
    ) throws -> Data {
        let parsed = MarkdownDocumentParser.parse(markdown)
        let deck = makeDeck(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            document: parsed
        )
        let allSlides = [Slide(
            title: [.text(deck.title)],
            content: deck.titleContent,
            notes: deck.titleNotes
        )] + deck.slides
        let noteSlideNumbers = allSlides.enumerated().compactMap {
            $0.element.notes.isEmpty ? nil : $0.offset + 1
        }

        var entries = baseEntries(
            title: deck.title,
            slideCount: allSlides.count,
            notesCount: noteSlideNumbers.count,
            theme: theme,
            language: documentLanguage
        )
        var mediaNumber = 1
        var allMedia: [MediaPart] = []

        for (offset, slide) in allSlides.enumerated() {
            let number = offset + 1
            let isTitleSlide = number == 1
            var context = SlideContext()
            let images = prepareImages(
                collectImages(in: slide.content),
                sourceDirectory: sourceDirectory
            )
            if images.count > 4 {
                throw PowerPointExportError.tooManyImages(slide.title.plainText)
            }
            let paragraphs = paragraphs(from: slide.content, language: documentLanguage)
            try validateFit(
                title: slide.title.plainText,
                paragraphs: paragraphs,
                imageCount: images.count,
                isTitleSlide: isTitleSlide
            )

            let built = slideXML(
                slide: slide,
                paragraphs: paragraphs,
                images: images,
                number: number,
                isTitleSlide: isTitleSlide,
                language: documentLanguage,
                mediaNumber: &mediaNumber,
                context: &context
            )
            entries["ppt/slides/slide\(number).xml"] = data(built)

            var fixedRelationships = [Relationship(
                id: "rId1",
                type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout",
                target: isTitleSlide ? "../slideLayouts/slideLayout1.xml" : "../slideLayouts/slideLayout2.xml"
            )]
            if !slide.notes.isEmpty {
                fixedRelationships.append(Relationship(
                    id: "rId2",
                    type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide",
                    target: "../notesSlides/notesSlide\(number).xml"
                ))
                entries["ppt/notesSlides/notesSlide\(number).xml"] = data(
                    notesSlideXML(blocks: slide.notes, language: documentLanguage)
                )
                entries["ppt/notesSlides/_rels/notesSlide\(number).xml.rels"] = data(
                    relationshipsXML([
                        Relationship(
                            id: "rId1",
                            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster",
                            target: "../notesMasters/notesMaster1.xml"
                        ),
                        Relationship(
                            id: "rId2",
                            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide",
                            target: "../slides/slide\(number).xml"
                        )
                    ])
                )
            }
            entries["ppt/slides/_rels/slide\(number).xml.rels"] = data(
                relationshipsXML(fixedRelationships + context.relationships)
            )
            for media in context.media {
                entries["ppt/media/\(media.fileName)"] = media.data
                allMedia.append(media)
            }
        }

        entries["[Content_Types].xml"] = data(contentTypesXML(
            slideCount: allSlides.count,
            noteSlideNumbers: noteSlideNumbers,
            media: allMedia
        ))
        return try PowerPointPackage.create(entries: entries)
    }

    // MARK: - Markdown to slides

    private static func makeDeck(title: String, document: ExportDocument) -> Deck {
        var deckTitle = title.isEmpty ? String(localized: "Presentation") : title
        var titleContent: [ExportBlock] = []
        var titleNotes: [ExportBlock] = []
        var titleInNotes = false
        var slides: [Slide] = []
        var current: Slide?
        var currentInNotes = false
        var acceptedDocumentTitle = false

        func finishCurrent() {
            if let current { slides.append(current) }
            current = nil
            currentInNotes = false
        }

        for block in document.blocks {
            if case .heading(let level, let content) = block, level == 2 {
                finishCurrent()
                current = Slide(title: content, content: [], notes: [])
                continue
            }

            if current == nil,
               case .heading(let level, let content) = block,
               level == 1,
               !acceptedDocumentTitle {
                let value = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { deckTitle = value }
                acceptedDocumentTitle = true
                continue
            }

            if current != nil {
                if case .thematicBreak = block, !currentInNotes {
                    currentInNotes = true
                } else if currentInNotes {
                    current?.notes.append(block)
                } else {
                    current?.content.append(block)
                }
            } else if case .thematicBreak = block, !titleInNotes {
                titleInNotes = true
            } else if titleInNotes {
                titleNotes.append(block)
            } else {
                titleContent.append(block)
            }
        }
        finishCurrent()

        return Deck(
            title: deckTitle,
            titleContent: titleContent,
            titleNotes: titleNotes,
            slides: slides
        )
    }

    private static func paragraphs(
        from blocks: [ExportBlock],
        language: String,
        level: Int = 0
    ) -> [Paragraph] {
        var result: [Paragraph] = []
        for block in blocks {
            switch block {
            case .heading(let headingLevel, let content):
                result.append(Paragraph(
                    runs: textRuns(content),
                    level: max(0, headingLevel - 3),
                    fontSize: headingLevel == 3 ? 2800 : 2400,
                    color: "accent1",
                    bold: true
                ))
            case .paragraph(let content):
                let runs = textRuns(content)
                if !runs.allSatisfy({ $0.text.isEmpty }) {
                    result.append(Paragraph(runs: runs))
                }
            case .list(let list):
                appendList(list, language: language, level: level, to: &result)
            case .table(let table):
                let headers = table.headers.map(\.plainText)
                if !headers.isEmpty {
                    result.append(Paragraph(
                        runs: [TextRun(text: headers.joined(separator: " | "), bold: true)],
                        bold: true
                    ))
                }
                for row in table.rows {
                    let cells = row.enumerated().map { index, value in
                        let text = value.plainText
                        guard index < headers.count, !headers[index].isEmpty else { return text }
                        return "\(headers[index]): \(text)"
                    }
                    result.append(Paragraph(runs: [TextRun(text: cells.joined(separator: "; "))]))
                }
            case .blockQuote(let children):
                var quoted = paragraphs(from: children, language: language, level: level)
                if !quoted.isEmpty {
                    quoted[0].runs.insert(TextRun(text: String(localized: "Quote: "), bold: true), at: 0)
                }
                result.append(contentsOf: quoted)
            case .codeBlock(let codeLanguage, let code):
                let prefix = codeLanguage.map { String(localized: "Code (\($0)):") + "\n" } ?? ""
                result.append(Paragraph(
                    runs: [TextRun(text: prefix + code, code: true)],
                    fontSize: 2000,
                    code: true
                ))
            case .thematicBreak:
                continue
            }
        }
        return result
    }

    private static func appendList(
        _ list: ExportList,
        language: String,
        level: Int,
        to paragraphs: inout [Paragraph]
    ) {
        for (offset, item) in list.items.enumerated() {
            var runs = textRuns(item.content)
            if let state = item.taskState {
                runs.insert(TextRun(
                    text: state.spokenPrefix(for: language) + " ",
                    bold: true
                ), at: 0)
            }
            paragraphs.append(Paragraph(
                runs: runs,
                level: min(level, 8),
                marker: list.isOrdered
                    ? .numbered(start: offset == 0 ? list.start : nil)
                    : .bullet
            ))
            for child in item.children {
                if case .list(let nested) = child {
                    appendList(nested, language: language, level: level + 1, to: &paragraphs)
                } else {
                    var children = self.paragraphs(from: [child], language: language, level: level + 1)
                    for index in children.indices { children[index].level = min(level + 1, 8) }
                    paragraphs.append(contentsOf: children)
                }
            }
        }
    }

    private static func textRuns(_ content: [ExportInline]) -> [TextRun] {
        var result: [TextRun] = []
        appendTextRuns(content, to: &result)
        return result
    }

    private static func appendTextRuns(
        _ content: [ExportInline],
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        hyperlink: String? = nil,
        to result: inout [TextRun]
    ) {
        for item in content {
            switch item {
            case .text(let text):
                result.append(TextRun(
                    text: text,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strikethrough,
                    hyperlink: hyperlink
                ))
            case .emphasis(let children):
                appendTextRuns(children, bold: bold, italic: true, underline: underline, strikethrough: strikethrough, hyperlink: hyperlink, to: &result)
            case .strong(let children):
                appendTextRuns(children, bold: true, italic: italic, underline: underline, strikethrough: strikethrough, hyperlink: hyperlink, to: &result)
            case .strikethrough(let children):
                appendTextRuns(children, bold: bold, italic: italic, underline: underline, strikethrough: true, hyperlink: hyperlink, to: &result)
            case .underline(let children):
                appendTextRuns(children, bold: bold, italic: italic, underline: true, strikethrough: strikethrough, hyperlink: hyperlink, to: &result)
            case .code(let text):
                result.append(TextRun(
                    text: text,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strikethrough,
                    code: true,
                    hyperlink: hyperlink
                ))
            case .link(let destination, let children):
                appendTextRuns(children, bold: bold, italic: italic, underline: true, strikethrough: strikethrough, hyperlink: destination, to: &result)
            case .image:
                continue
            case .lineBreak:
                result.append(TextRun(text: "\n", bold: bold, italic: italic, underline: underline, strikethrough: strikethrough, hyperlink: hyperlink))
            }
        }
    }

    private static func collectImages(in blocks: [ExportBlock]) -> [ExportImage] {
        var images: [ExportImage] = []
        func collect(_ inlines: [ExportInline]) {
            for inline in inlines {
                switch inline {
                case .image(let image): images.append(image)
                case .emphasis(let children), .strong(let children),
                     .strikethrough(let children), .underline(let children),
                     .link(_, let children): collect(children)
                case .text, .code, .lineBreak: break
                }
            }
        }
        for block in blocks {
            switch block {
            case .heading(_, let content), .paragraph(let content): collect(content)
            case .list(let list):
                for item in list.items {
                    collect(item.content)
                    images.append(contentsOf: collectImages(in: item.children))
                }
            case .table(let table):
                for cell in table.headers { collect(cell) }
                for row in table.rows { for cell in row { collect(cell) } }
            case .blockQuote(let children): images.append(contentsOf: collectImages(in: children))
            case .codeBlock, .thematicBreak: break
            }
        }
        return images
    }

    private static func prepareImages(
        _ images: [ExportImage],
        sourceDirectory: URL?
    ) -> [PreparedImage] {
        images.compactMap { image in
            guard let resolved = ExportImageResource.resolveManagedAsset(
                source: image.source,
                sourceDirectory: sourceDirectory
            ) else {
                return nil
            }
            let fileExtension: String
            switch resolved.mediaType {
            case "image/jpeg": fileExtension = "jpg"
            case "image/png": fileExtension = "png"
            case "image/svg+xml": fileExtension = "svg"
            default: return nil
            }
            return PreparedImage(
                image: image,
                data: resolved.data,
                mediaType: resolved.mediaType,
                fileExtension: fileExtension,
                ratio: imageRatio(data: resolved.data, mediaType: resolved.mediaType)
            )
        }
    }

    private static func validateFit(
        title: String,
        paragraphs: [Paragraph],
        imageCount: Int,
        isTitleSlide: Bool
    ) throws {
        if title.count > (isTitleSlide ? 70 : 82) {
            throw PowerPointExportError.slideTooFull(title)
        }
        let charactersPerLine = imageCount > 0 ? 42 : 78
        let estimatedLines = paragraphs.reduce(0) { total, paragraph in
            let count = max(1, paragraph.runs.reduce(0) { $0 + $1.text.count })
            let lines = max(1, Int(ceil(Double(count) / Double(charactersPerLine - paragraph.level * 4))))
            return total + lines + (paragraph.fontSize >= 2800 ? 1 : 0)
        }
        let maximum = isTitleSlide ? 7 : (imageCount > 0 ? 12 : 16)
        if estimatedLines > maximum {
            throw PowerPointExportError.slideTooFull(title)
        }
    }

    // MARK: - Slides

    private static func slideXML(
        slide: Slide,
        paragraphs: [Paragraph],
        images: [PreparedImage],
        number: Int,
        isTitleSlide: Bool,
        language: String,
        mediaNumber: inout Int,
        context: inout SlideContext
    ) -> String {
        let titlePosition = isTitleSlide
            ? (x: 914_400, y: 1_200_000, width: 10_363_200, height: 1_400_000)
            : (x: 548_640, y: 274_320, width: 11_094_720, height: 822_960)
        let hasText = !paragraphs.isEmpty
        let hasImages = !images.isEmpty
        let bodyPosition: (x: Int, y: Int, width: Int, height: Int)
        if isTitleSlide {
            bodyPosition = (1_371_600, 2_800_000, 9_448_800, 1_400_000)
        } else if hasImages && hasText {
            bodyPosition = (731_520, 1_371_600, 5_760_000, 4_800_000)
        } else {
            bodyPosition = (731_520, 1_371_600, 10_728_000, 4_900_000)
        }

        var shapes = titleShapeXML(
            content: slide.title,
            position: titlePosition,
            isTitleSlide: isTitleSlide,
            language: language,
            context: &context
        )
        if hasText {
            shapes += textShapeXML(
                paragraphs: paragraphs,
                position: bodyPosition,
                placeholderType: isTitleSlide ? "subTitle" : "body",
                placeholderIndex: 1,
                name: isTitleSlide ? "Subtitle" : "Content",
                language: language,
                context: &context
            )
        }

        if hasImages {
            for (index, image) in images.enumerated() {
                let added = context.addImage(
                    image,
                    mediaNumber: mediaNumber
                )
                mediaNumber += 1
                let frame = imageFrame(
                    index: index,
                    count: images.count,
                    hasText: hasText,
                    ratio: added.ratio
                )
                shapes += pictureXML(
                    image: image.image,
                    relationshipID: added.id,
                    shapeID: 100 + index,
                    position: frame
                )
            }
        }

        return xmlHeader + """
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:adec="http://schemas.microsoft.com/office/drawing/2017/decorative"><p:cSld><p:bg><p:bgPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>\(groupShapeRoot)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
        """
    }

    private static func titleShapeXML(
        content: [ExportInline],
        position: (x: Int, y: Int, width: Int, height: Int),
        isTitleSlide: Bool,
        language: String,
        context: inout SlideContext
    ) -> String {
        let paragraph = Paragraph(
            runs: textRuns(content),
            fontSize: isTitleSlide ? 5400 : 4000,
            color: "accent1",
            bold: true
        )
        return textShapeXML(
            paragraphs: [paragraph],
            position: position,
            placeholderType: isTitleSlide ? "ctrTitle" : "title",
            placeholderIndex: 0,
            name: isTitleSlide ? "Title" : "Slide title",
            language: language,
            context: &context
        )
    }

    private static func textShapeXML(
        paragraphs: [Paragraph],
        position: (x: Int, y: Int, width: Int, height: Int),
        placeholderType: String,
        placeholderIndex: Int,
        name: String,
        language: String,
        context: inout SlideContext
    ) -> String {
        let paragraphXML = paragraphs.map {
            drawingParagraphXML($0, language: language, context: &context)
        }.joined()
        let placeholderIndexXML = placeholderIndex == 0 ? "" : " idx=\"\(placeholderIndex)\""
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(placeholderIndex + 2)" name="\(xmlAttribute(name))"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="\(placeholderType)"\(placeholderIndexXML)/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="\(position.x)" y="\(position.y)"/><a:ext cx="\(position.width)" cy="\(position.height)"/></a:xfrm></p:spPr><p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="t"/><a:lstStyle/>\(paragraphXML)</p:txBody></p:sp>
        """
    }

    private static func drawingParagraphXML(
        _ paragraph: Paragraph,
        language: String,
        context: inout SlideContext
    ) -> String {
        let marker: String
        switch paragraph.marker {
        case .none: marker = "<a:buNone/>"
        case .bullet:
            marker = "<a:buSzPct val=\"100000\"/><a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/>"
        case .numbered(let start):
            if let start {
                marker = "<a:buSzPct val=\"100000\"/><a:buFont typeface=\"Arial\"/><a:buAutoNum type=\"arabicPeriod\" startAt=\"\(max(1, start))\"/>"
            } else {
                marker = "<a:buSzPct val=\"100000\"/><a:buFont typeface=\"Arial\"/><a:buAutoNum type=\"arabicPeriod\"/>"
            }
        }
        let margin = paragraph.markerIsNone ? 0 : 457_200 + paragraph.level * 365_760
        let indent = paragraph.markerIsNone ? 0 : -228_600
        let properties = "<a:pPr lvl=\"\(min(paragraph.level, 8))\" marL=\"\(margin)\" indent=\"\(indent)\"><a:spcAft><a:spcPts val=\"700\"/></a:spcAft>\(marker)</a:pPr>"
        let runs = paragraph.runs.map { run -> String in
            var attributes = "lang=\"\(xmlAttribute(language))\" sz=\"\(paragraph.fontSize)\""
            if run.bold || paragraph.bold { attributes += " b=\"1\"" }
            if run.italic { attributes += " i=\"1\"" }
            if run.underline || run.hyperlink != nil { attributes += " u=\"sng\"" }
            if run.strikethrough { attributes += " strike=\"sngStrike\"" }
            let typeface = run.code || paragraph.code ? "<a:latin typeface=\"Courier New\"/>" : "<a:latin typeface=\"Arial\"/>"
            let color = run.hyperlink == nil ? paragraph.color : "hlink"
            let hyperlinkXML: String
            if let target = run.hyperlink, !target.isEmpty {
                hyperlinkXML = "<a:hlinkClick r:id=\"\(context.addHyperlink(target))\"/>"
            } else {
                hyperlinkXML = ""
            }
            return "<a:r><a:rPr \(attributes)><a:solidFill><a:schemeClr val=\"\(color)\"/></a:solidFill>\(typeface)\(hyperlinkXML)</a:rPr><a:t>\(xmlText(run.text))</a:t></a:r>"
        }.joined()
        return "<a:p>\(properties)\(runs)<a:endParaRPr lang=\"\(xmlAttribute(language))\" sz=\"\(paragraph.fontSize)\"><a:solidFill><a:schemeClr val=\"\(paragraph.color)\"/></a:solidFill><a:latin typeface=\"Arial\"/></a:endParaRPr></a:p>"
    }

    private static func pictureXML(
        image: ExportImage,
        relationshipID: String,
        shapeID: Int,
        position: (x: Int, y: Int, width: Int, height: Int)
    ) -> String {
        let description = image.alternativeText ?? ""
        let decorative = image.isDecorative
            ? "<a:extLst><a:ext uri=\"{C183D7F6-B498-43B3-948B-1728B52AA6E4}\"><adec:decorative val=\"1\"/></a:ext></a:extLst>"
            : ""
        return """
        <p:pic><p:nvPicPr><p:cNvPr id="\(shapeID)" name="Picture \(shapeID)" descr="\(xmlAttribute(description))">\(decorative)</p:cNvPr><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="\(relationshipID)"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="\(position.x)" y="\(position.y)"/><a:ext cx="\(position.width)" cy="\(position.height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:ln><a:schemeClr val="accent2"/></a:ln></p:spPr></p:pic>
        """
    }

    private static func imageFrame(
        index: Int,
        count: Int,
        hasText: Bool,
        ratio: Double
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let area = hasText
            ? (x: 6_850_000, y: 1_350_000, width: 4_800_000, height: 4_900_000)
            : (x: 900_000, y: 1_300_000, width: 10_400_000, height: 5_000_000)
        let columns = count == 1 ? 1 : 2
        let rows = Int(ceil(Double(count) / Double(columns)))
        let gap = 180_000
        let cellWidth = (area.width - (columns - 1) * gap) / columns
        let cellHeight = (area.height - (rows - 1) * gap) / rows
        let column = index % columns
        let row = index / columns
        let cellX = area.x + column * (cellWidth + gap)
        let cellY = area.y + row * (cellHeight + gap)
        let cellRatio = Double(cellWidth) / Double(cellHeight)
        let width: Int
        let height: Int
        if ratio > cellRatio {
            width = cellWidth
            height = max(1, Int(Double(width) / ratio))
        } else {
            height = cellHeight
            width = max(1, Int(Double(height) * ratio))
        }
        return (
            cellX + (cellWidth - width) / 2,
            cellY + (cellHeight - height) / 2,
            width,
            height
        )
    }

    // MARK: - Notes

    private static func notesSlideXML(blocks: [ExportBlock], language: String) -> String {
        let notes = paragraphs(from: blocks, language: language).map { paragraph in
            let text = paragraph.runs.map(\.text).joined()
            return "<a:p><a:r><a:rPr lang=\"\(xmlAttribute(language))\" sz=\"1200\"><a:latin typeface=\"Arial\"/></a:rPr><a:t>\(xmlText(text))</a:t></a:r><a:endParaRPr lang=\"\(xmlAttribute(language))\" sz=\"1200\"/></a:p>"
        }.joined()
        let slideImage = notesPlaceholderXML(id: 2, name: "Slide image", type: "sldImg", index: 2)
        let notesBody = """
        <p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes body"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="3"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(notes)</p:txBody></p:sp>
        """
        let slideNumber = notesPlaceholderXML(id: 4, name: "Slide number", type: "sldNum", index: 5)
        return xmlHeader + """
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree>\(groupShapeRoot)\(slideImage)\(notesBody)\(slideNumber)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>
        """
    }

    // MARK: - Package parts

    private static func baseEntries(
        title: String,
        slideCount: Int,
        notesCount: Int,
        theme: PowerPointTheme,
        language: String
    ) -> [String: Data] {
        let hasNotes = notesCount > 0
        var entries: [String: Data] = [
            "_rels/.rels": data(packageRelationshipsXML),
            "docProps/core.xml": data(corePropertiesXML(title: title, language: language)),
            "docProps/app.xml": data(appPropertiesXML(
                slideCount: slideCount,
                notesCount: notesCount
            )),
            "ppt/presentation.xml": data(presentationXML(
                slideCount: slideCount,
                hasNotes: hasNotes
            )),
            "ppt/_rels/presentation.xml.rels": data(presentationRelationshipsXML(
                slideCount: slideCount,
                hasNotes: hasNotes
            )),
            "ppt/presProps.xml": data(presentationPropertiesXML),
            "ppt/viewProps.xml": data(viewPropertiesXML),
            "ppt/tableStyles.xml": data(tableStylesXML),
            "ppt/theme/theme1.xml": data(themeXML(theme)),
            "ppt/slideMasters/slideMaster1.xml": data(slideMasterXML),
            "ppt/slideMasters/_rels/slideMaster1.xml.rels": data(slideMasterRelationshipsXML),
            "ppt/slideLayouts/slideLayout1.xml": data(slideLayoutXML(isTitle: true)),
            "ppt/slideLayouts/slideLayout2.xml": data(slideLayoutXML(isTitle: false)),
            "ppt/slideLayouts/_rels/slideLayout1.xml.rels": data(slideLayoutRelationshipsXML),
            "ppt/slideLayouts/_rels/slideLayout2.xml.rels": data(slideLayoutRelationshipsXML)
        ]
        if hasNotes {
            entries["ppt/notesMasters/notesMaster1.xml"] = data(
                notesMasterXML(language: language)
            )
            entries["ppt/notesMasters/_rels/notesMaster1.xml.rels"] = data(
                notesMasterRelationshipsXML
            )
        }
        return entries
    }

    private static func presentationXML(slideCount: Int, hasNotes: Bool) -> String {
        let slides = (1...slideCount).map { number in
            "<p:sldId id=\"\(255 + number)\" r:id=\"rId\(number + 1)\"/>"
        }.joined()
        let notesMaster = hasNotes
            ? "<p:notesMasterIdLst><p:notesMasterId r:id=\"rId\(slideCount + 2)\"/></p:notesMasterIdLst>"
            : ""
        return xmlHeader + """
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>\(slides)</p:sldIdLst>\(notesMaster)<p:sldSz cx="\(slideWidth)" cy="\(slideHeight)"/><p:notesSz cx="\(notesWidth)" cy="\(notesHeight)"/>\(defaultTextStyleXML)</p:presentation>
        """
    }

    private static func presentationRelationshipsXML(slideCount: Int, hasNotes: Bool) -> String {
        var relationships = [Relationship(
            id: "rId1",
            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster",
            target: "slideMasters/slideMaster1.xml"
        )]
        relationships += (1...slideCount).map { number in
            Relationship(id: "rId\(number + 1)", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide", target: "slides/slide\(number).xml")
        }
        var nextRelationship = slideCount + 2
        if hasNotes {
            relationships.append(Relationship(
                id: "rId\(nextRelationship)",
                type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster",
                target: "notesMasters/notesMaster1.xml"
            ))
            nextRelationship += 1
        }
        relationships += [
            Relationship(id: "rId\(nextRelationship)", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps", target: "presProps.xml"),
            Relationship(id: "rId\(nextRelationship + 1)", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps", target: "viewProps.xml"),
            Relationship(id: "rId\(nextRelationship + 2)", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", target: "theme/theme1.xml"),
            Relationship(id: "rId\(nextRelationship + 3)", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles", target: "tableStyles.xml")
        ]
        return relationshipsXML(relationships)
    }

    private static var slideMasterXML: String {
        xmlHeader + """
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld name="ghostWriter"><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\(groupShapeRoot)</p:spTree></p:cSld><p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" hlink="hlink" tx1="dk1" tx2="dk2"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/><p:sldLayoutId id="2147483650" r:id="rId2"/></p:sldLayoutIdLst><p:hf hdr="0" ftr="0" dt="0" sldNum="0"/><p:txStyles><p:titleStyle>\(textStyleLevels(fontSize: 4000, color: "accent1", bold: true))</p:titleStyle><p:bodyStyle>\(textStyleLevels(fontSize: 2400, color: "tx1", bulletIndent: true))</p:bodyStyle><p:otherStyle><a:defPPr><a:defRPr lang="en-US" sz="2400"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="Arial"/><a:ea typeface="Arial"/><a:cs typeface="Arial"/></a:defRPr></a:defPPr>\(textStyleLevels(fontSize: 2400, color: "tx1"))</p:otherStyle></p:txStyles></p:sldMaster>
        """
    }

    private static let slideMasterRelationshipsXML = relationshipsXML([
        Relationship(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", target: "../slideLayouts/slideLayout1.xml"),
        Relationship(id: "rId2", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", target: "../slideLayouts/slideLayout2.xml"),
        Relationship(id: "rId3", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", target: "../theme/theme1.xml")
    ])

    private static func slideLayoutXML(isTitle: Bool) -> String {
        let layoutType = isTitle ? "title" : "obj"
        let name = isTitle ? "Title Slide" : "Title and Content"
        let titlePlaceholder = layoutPlaceholderXML(
            id: 2,
            name: isTitle ? "Title" : "Slide title",
            type: isTitle ? "ctrTitle" : "title",
            index: 0,
            position: isTitle
                ? (914_400, 1_200_000, 10_363_200, 1_400_000)
                : (548_640, 274_320, 11_094_720, 822_960)
        )
        let bodyPlaceholder = layoutPlaceholderXML(
            id: 3,
            name: isTitle ? "Subtitle" : "Content",
            type: isTitle ? "subTitle" : "body",
            index: 1,
            position: isTitle
                ? (1_371_600, 2_800_000, 9_448_800, 1_400_000)
                : (731_520, 1_371_600, 10_728_000, 4_900_000)
        )
        return xmlHeader + """
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="\(layoutType)" preserve="1"><p:cSld name="\(name)"><p:spTree>\(groupShapeRoot)\(titlePlaceholder)\(bodyPlaceholder)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """
    }

    private static func layoutPlaceholderXML(
        id: Int,
        name: String,
        type: String,
        index: Int,
        position: (x: Int, y: Int, width: Int, height: Int)
    ) -> String {
        let placeholderIndexXML = index == 0 ? "" : " idx=\"\(index)\""
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="\(xmlAttribute(name))"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="\(type)"\(placeholderIndexXML)/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="\(position.x)" y="\(position.y)"/><a:ext cx="\(position.width)" cy="\(position.height)"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>
        """
    }

    private static let slideLayoutRelationshipsXML = relationshipsXML([
        Relationship(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster", target: "../slideMasters/slideMaster1.xml")
    ])

    private static func notesMasterXML(language: String) -> String {
        let placeholders = [
            notesMasterPlaceholderXML(id: 2, name: "Header", type: "hdr", index: 0, x: 685_800, y: 440_000, width: 2_700_000, height: 300_000, language: language),
            notesMasterPlaceholderXML(id: 3, name: "Date", type: "dt", index: 1, x: 3_450_000, y: 440_000, width: 2_700_000, height: 300_000, language: language),
            notesMasterPlaceholderXML(id: 4, name: "Slide image", type: "sldImg", index: 2, x: 685_800, y: 1_143_000, width: 5_486_400, height: 3_086_100, language: language),
            notesMasterPlaceholderXML(id: 5, name: "Notes body", type: "body", index: 3, x: 685_800, y: 4_400_550, width: 5_486_400, height: 3_600_450, language: language),
            notesMasterPlaceholderXML(id: 6, name: "Footer", type: "ftr", index: 4, x: 685_800, y: 8_450_000, width: 2_700_000, height: 300_000, language: language),
            notesMasterPlaceholderXML(id: 7, name: "Slide number", type: "sldNum", index: 5, x: 3_450_000, y: 8_450_000, width: 2_700_000, height: 300_000, language: language)
        ].joined()
        return xmlHeader + """
        <p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\(groupShapeRoot)\(placeholders)</p:spTree></p:cSld><p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" hlink="hlink" tx1="dk1" tx2="dk2"/><p:hf hdr="0" ftr="0" dt="0" sldNum="0"/><p:notesStyle>\(textStyleLevels(fontSize: 1200, color: "tx1", bulletIndent: true, language: language))</p:notesStyle></p:notesMaster>
        """
    }

    private static let notesMasterRelationshipsXML = relationshipsXML([
        Relationship(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", target: "../theme/theme1.xml")
    ])

    private static var defaultTextStyleXML: String {
        "<p:defaultTextStyle><a:defPPr><a:defRPr lang=\"en-US\"/></a:defPPr>\(textStyleLevels(fontSize: 1800, color: "tx1"))</p:defaultTextStyle>"
    }

    private static func textStyleLevels(
        fontSize: Int,
        color: String,
        bold: Bool = false,
        bulletIndent: Bool = false,
        language: String = "en-US"
    ) -> String {
        (1...9).map { level in
            let margin = bulletIndent ? 457_200 + (level - 1) * 365_760 : 0
            let indent = bulletIndent ? -228_600 : 0
            let boldAttribute = bold ? " b=\"1\"" : ""
            return "<a:lvl\(level)pPr marL=\"\(margin)\" indent=\"\(indent)\" algn=\"l\" defTabSz=\"914400\" rtl=\"0\" eaLnBrk=\"1\" latinLnBrk=\"0\" hangingPunct=\"1\"><a:defRPr lang=\"\(xmlAttribute(language))\" sz=\"\(fontSize)\" kern=\"1200\"\(boldAttribute)><a:solidFill><a:schemeClr val=\"\(color)\"/></a:solidFill><a:latin typeface=\"Arial\"/><a:ea typeface=\"Arial\"/><a:cs typeface=\"Arial\"/></a:defRPr></a:lvl\(level)pPr>"
        }.joined()
    }

    private static func notesPlaceholderXML(
        id: Int,
        name: String,
        type: String,
        index: Int
    ) -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(xmlAttribute(name))\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"\(type)\" idx=\"\(index)\"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang=\"en-US\"/></a:p></p:txBody></p:sp>"
    }

    private static func notesMasterPlaceholderXML(
        id: Int,
        name: String,
        type: String,
        index: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        language: String
    ) -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(xmlAttribute(name))\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"\(type)\" idx=\"\(index)\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang=\"\(xmlAttribute(language))\"/></a:p></p:txBody></p:sp>"
    }

    private static func themeXML(_ theme: PowerPointTheme) -> String {
        let palette = theme.palette
        return xmlHeader + """
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="ghostWriter \(xmlAttribute(theme.label))"><a:themeElements><a:clrScheme name="ghostWriter \(xmlAttribute(theme.label))"><a:dk1><a:srgbClr val="\(palette.text)"/></a:dk1><a:lt1><a:srgbClr val="\(palette.background)"/></a:lt1><a:dk2><a:srgbClr val="\(palette.secondaryText)"/></a:dk2><a:lt2><a:srgbClr val="\(palette.accentSoft)"/></a:lt2><a:accent1><a:srgbClr val="\(palette.accent)"/></a:accent1><a:accent2><a:srgbClr val="\(palette.border)"/></a:accent2><a:accent3><a:srgbClr val="\(palette.link)"/></a:accent3><a:accent4><a:srgbClr val="\(palette.secondaryText)"/></a:accent4><a:accent5><a:srgbClr val="\(palette.accent)"/></a:accent5><a:accent6><a:srgbClr val="\(palette.border)"/></a:accent6><a:hlink><a:srgbClr val="\(palette.link)"/></a:hlink><a:folHlink><a:srgbClr val="\(palette.link)"/></a:folHlink></a:clrScheme><a:fontScheme name="ghostWriter"><a:majorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface="Arial"/></a:majorFont><a:minorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface="Arial"/></a:minorFont></a:fontScheme><a:fmtScheme name="ghostWriter"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln><a:ln w="25400"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln><a:ln w="38100"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>
        """
    }

    private static func contentTypesXML(
        slideCount: Int,
        noteSlideNumbers: [Int],
        media: [MediaPart]
    ) -> String {
        var defaults: [String: String] = [:]
        for part in media {
            defaults[URL(fileURLWithPath: part.fileName).pathExtension.lowercased()] = part.mediaType
        }
        let imageDefaults = defaults.keys.sorted().map { ext in
            "<Default Extension=\"\(xmlAttribute(ext))\" ContentType=\"\(xmlAttribute(defaults[ext] ?? "application/octet-stream"))\"/>"
        }.joined()
        let slides = (1...slideCount).map {
            "<Override PartName=\"/ppt/slides/slide\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
        }.joined()
        let notes = noteSlideNumbers.map {
            "<Override PartName=\"/ppt/notesSlides/notesSlide\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>"
        }.joined()
        let notesPackageParts = noteSlideNumbers.isEmpty ? "" : "<Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml\"/>"
        return xmlHeader + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>\(imageDefaults)<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/><Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/><Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/slideLayouts/slideLayout2.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\(notesPackageParts)\(slides)\(notes)<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
        """
    }

    private static let packageRelationshipsXML = xmlHeader + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
    """

    private static func corePropertiesXML(title: String, language: String) -> String {
        xmlHeader + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(xmlText(title))</dc:title><dc:creator>ghostWriter</dc:creator><dc:language>\(xmlText(language))</dc:language><cp:lastModifiedBy>ghostWriter</cp:lastModifiedBy></cp:coreProperties>"
    }

    private static func appPropertiesXML(slideCount: Int, notesCount: Int) -> String {
        xmlHeader + "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>ghostWriter</Application><PresentationFormat>Widescreen</PresentationFormat><Slides>\(slideCount)</Slides><Notes>\(notesCount)</Notes></Properties>"
    }

    private static let presentationPropertiesXML = xmlHeader + "<p:presentationPr xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"/>"
    private static let viewPropertiesXML = xmlHeader + "<p:viewPr xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" lastView=\"sldView\"><p:normalViewPr horzBarState=\"maximized\"><p:restoredLeft sz=\"15987\"/><p:restoredTop sz=\"94660\"/></p:normalViewPr><p:slideViewPr><p:cSldViewPr snapToGrid=\"0\" snapToObjects=\"1\"><p:cViewPr varScale=\"1\"><p:scale><a:sx n=\"100\" d=\"100\"/><a:sy n=\"100\" d=\"100\"/></p:scale><p:origin x=\"0\" y=\"0\"/></p:cViewPr><p:guideLst/></p:cSldViewPr></p:slideViewPr><p:notesTextViewPr><p:cViewPr><p:scale><a:sx n=\"1\" d=\"1\"/><a:sy n=\"1\" d=\"1\"/></p:scale><p:origin x=\"0\" y=\"0\"/></p:cViewPr></p:notesTextViewPr><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>"
    private static let tableStylesXML = xmlHeader + "<a:tblStyleLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>"

    private static func relationshipsXML(_ relationships: [Relationship]) -> String {
        let body = relationships.map { relationship in
            let mode = relationship.external ? " TargetMode=\"External\"" : ""
            return "<Relationship Id=\"\(relationship.id)\" Type=\"\(relationship.type)\" Target=\"\(xmlAttribute(relationship.target))\"\(mode)/>"
        }.joined()
        return xmlHeader + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(body)</Relationships>"
    }

    private static let groupShapeRoot = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    private static func imageRatio(data: Data, mediaType: String) -> Double {
        if mediaType != "image/svg+xml",
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Double,
           let height = properties[kCGImagePropertyPixelHeight] as? Double,
           width > 0, height > 0 {
            return width / height
        }
        if let text = String(data: data, encoding: .utf8),
           let match = text.firstMatch(of: /viewBox\s*=\s*["']\s*[-\d.]+\s+[-\d.]+\s+([\d.]+)\s+([\d.]+)\s*["']/),
           let width = Double(match.1), let height = Double(match.2), height > 0 {
            return width / height
        }
        return 4.0 / 3.0
    }

    private static func data(_ string: String) -> Data { Data(string.utf8) }

    private static func xmlText(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func xmlAttribute(_ value: String) -> String {
        xmlText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

nonisolated enum PowerPointExportError: LocalizedError, Equatable, Sendable {
    case couldNotCreateDocument
    case slideTooFull(String)
    case tooManyImages(String)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDocument:
            return String(localized: "The PowerPoint presentation could not be created.")
        case .slideTooFull(let title):
            return String(localized: "The slide “\(title)” contains too much content. Add another level 2 heading.")
        case .tooManyImages(let title):
            return String(localized: "The slide “\(title)” contains more than four images. Add another level 2 heading.")
        }
    }
}
