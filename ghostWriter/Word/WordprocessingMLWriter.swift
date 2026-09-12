import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum WordprocessingMLWriter {
    private struct NumberingKey: Hashable {
        var identifier: String
        var isBullet: Bool
        var start: Int
    }

    private struct HyperlinkRelationship {
        var id: String
        var target: String
    }

    private struct ImagePart {
        var id: String
        var fileName: String
        var data: Data
        var contentType: String
    }

    private struct WritingContext {
        var sourceDirectory: URL?
        var language: String?
        var theme: WordExportTheme?
        var openingRunStyle: WordThemeStyle?
        var inTable = false
        var hyperlinks: [HyperlinkRelationship] = []
        var images: [ImagePart] = []

        mutating func hyperlinkID(for target: String) -> String {
            let id = "rIdHyperlink\(hyperlinks.count + 1)"
            hyperlinks.append(HyperlinkRelationship(id: id, target: target))
            return id
        }

        mutating func addImage(_ image: WordImage) -> ImagePart? {
            guard let data = image.data ?? localImageData(
                target: image.externalTarget ?? image.fileName,
                sourceDirectory: sourceDirectory
            ), data.count <= Int(WordPackage.maximumEntrySize) else { return nil }
            let sourceName = URL(fileURLWithPath: image.fileName).lastPathComponent
            guard let ext = normalizedImageExtension(sourceName),
                  isDecodableImage(data, matching: ext) else { return nil }
            let fileName = "image\(images.count + 1).\(ext)"
            let part = ImagePart(
                id: "rIdImage\(images.count + 1)",
                fileName: fileName,
                data: data,
                contentType: imageContentType(for: ext)
            )
            images.append(part)
            return part
        }
    }

    static func write(
        title: String,
        document: WordDocumentModel,
        sourceDirectory: URL? = nil,
        documentLanguage: String = DocumentLanguage.resolvedTag(""),
        theme: WordExportTheme? = nil
    ) throws -> Data {
        let numberingKeys = try collectNumberingKeys(document.blocks)
        let numberingIDs = Dictionary(
            uniqueKeysWithValues: numberingKeys.enumerated().map { ($0.element, $0.offset + 1) }
        )
        var context = WritingContext(sourceDirectory: sourceDirectory, theme: theme)
        let body = try document.blocks.map {
            try blockXML($0, numberingIDs: numberingIDs, context: &context)
        }.joined()

        let hyperlinkXML = context.hyperlinks.map { relationship in
            "<Relationship Id=\"\(relationship.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(xmlAttribute(relationship.target))\" TargetMode=\"External\"/>"
        }.joined()
        let imageXML = context.images.map { image in
            "<Relationship Id=\"\(image.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(xmlAttribute(image.fileName))\"/>"
        }.joined()

        let pageParts = pageContentParts(theme)
        let pageRelationships = pageParts.map { part in
            "<Relationship Id=\"rId\(part.name)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(part.kind)\" Target=\"\(part.name).xml\"/>"
        }.joined()
        let pageOverrides = pageParts.map { part in
            "<Override PartName=\"/word/\(part.name).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\(part.kind)+xml\"/>"
        }.joined()
        let documentXML = xmlHeader + """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" xmlns:adec="http://schemas.microsoft.com/office/drawing/2017/decorative"><w:body>\(body)\(pageXML(theme?.page, parts: pageParts, differentFirstPage: theme?.differentFirstPage == true))</w:body></w:document>
        """
        let documentRelationships = xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>\(hyperlinkXML)\(imageXML)\(pageRelationships)</Relationships>
        """

        var entries: [String: Data] = [
            "[Content_Types].xml": data(contentTypesXML(images: context.images).replacingOccurrences(of: "</Types>", with: pageOverrides + "</Types>")),
            "_rels/.rels": data(packageRelationshipsXML),
            "docProps/core.xml": data(corePropertiesXML(title: title, language: documentLanguage)),
            "docProps/app.xml": data(appPropertiesXML),
            "word/document.xml": data(documentXML),
            "word/_rels/document.xml.rels": data(documentRelationships),
            "word/styles.xml": data(stylesXML(language: documentLanguage, theme: theme)),
            "word/numbering.xml": data(try numberingXML(keys: numberingKeys))
        ]
        for image in context.images {
            entries["word/media/\(image.fileName)"] = image.data
        }
        for part in pageParts { entries["word/\(part.name).xml"] = data(part.xml) }
        return try WordPackage.create(entries: entries)
    }

    private static func blockXML(
        _ block: WordBlock,
        numberingIDs: [NumberingKey: Int],
        context: inout WritingContext
    ) throws -> String {
        try Task.checkCancellation()
        switch block {
        case .paragraph(let paragraph):
            return try paragraphXML(
                paragraph,
                numberingIDs: numberingIDs,
                context: &context
            )
        case .table(let table):
            return try tableXML(
                table,
                numberingIDs: numberingIDs,
                context: &context
            )
        }
    }

    private static func paragraphXML(
        _ paragraph: WordParagraph,
        numberingIDs: [NumberingKey: Int],
        context: inout WritingContext
    ) throws -> String {
        if paragraph.isThematicSeparator && paragraph.runs.isEmpty && !paragraph.pageBreakBefore { return "" }
        let previousOpeningStyle = context.openingRunStyle
        let openingStyle: WordThemeStyle?
        if context.theme?.title != nil, context.theme?.subtitle != nil {
            openingStyle = paragraph.openingStyle == "title" ? context.theme?.title
                : paragraph.openingStyle == "subtitle" ? context.theme?.subtitle : nil
        } else { openingStyle = nil }
        context.openingRunStyle = openingStyle
        let baseStyle: WordThemeStyle? = paragraph.headingLevel.flatMap { context.theme?.headings?[String($0)] }
            ?? (paragraph.isCodeBlock ? context.theme?.code : paragraph.isBlockQuote ? context.theme?.quote : paragraph.list != nil ? context.theme?.list : nil)
        let pageBreakAfter = !context.inTable && (openingStyle?.pageBreakAfter ?? baseStyle?.pageBreakAfter ?? context.theme?.body?.pageBreakAfter ?? false)
        let previousDirectory = context.sourceDirectory
        let previousLanguage = context.language
        if let directory = paragraph.sourceDirectory { context.sourceDirectory = directory }
        context.language = paragraph.language
        defer {
            context.openingRunStyle = previousOpeningStyle
            context.sourceDirectory = previousDirectory
            context.language = previousLanguage
        }
        var properties = ""
        if let level = paragraph.headingLevel {
            properties += "<w:pStyle w:val=\"Heading\(max(1, min(6, level)))\"/>"
        } else if paragraph.isBlockQuote {
            properties += "<w:pStyle w:val=\"Quote\"/>"
        } else if paragraph.isCodeBlock {
            properties += "<w:pStyle w:val=\"HTMLPreformatted\"/>"
        }
        if paragraph.list != nil && context.theme?.list != nil {
            properties += "<w:pStyle w:val=\"ListParagraph\"/>"
        }
        var directStyle = openingStyle
        if paragraph.pageBreakBefore {
            if directStyle == nil { directStyle = WordThemeStyle() }
            directStyle?.pageBreakBefore = true
        }
        properties += styleParagraphProperties(directStyle)
        if let list = paragraph.list {
            let key: NumberingKey
            switch list.kind {
            case .bullet:
                key = NumberingKey(identifier: list.identifier, isBullet: true, start: 1)
            case .numbered(let start):
                key = NumberingKey(identifier: list.identifier, isBullet: false, start: start)
            }
            if let numberID = numberingIDs[key] {
                properties += "<w:numPr><w:ilvl w:val=\"\(max(0, min(8, list.level)))\"/><w:numId w:val=\"\(numberID)\"/></w:numPr>"
            }
        }
        if paragraph.isThematicSeparator { properties += "<w:jc w:val=\"center\"/>" }
        let pPr = properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>"
        let runs = try paragraph.runs.map {
            try Task.checkCancellation()
            return runXML($0, context: &context)
        }.joined()
        return "<w:p>\(pPr)\(runs)\(pageBreakAfter ? "<w:r><w:br w:type=\"page\"/></w:r>" : "")</w:p>"
    }

    private static func runXML(
        _ run: WordRun,
        context: inout WritingContext
    ) -> String {
        if let image = run.image {
            if let part = context.addImage(image) {
                return imageRunXML(
                    image,
                    relationshipID: part.id,
                    imageNumber: context.images.count,
                    data: part.data,
                    page: context.theme?.page
                )
            }
            var fallback = run
            fallback.image = nil
            fallback.text = image.alternativeText.map { "Image: \($0)" } ?? "Image"
            if let target = image.externalTarget,
               (target.lowercased().hasPrefix("http://")
                    || target.lowercased().hasPrefix("https://")) {
                fallback.hyperlink = target
            }
            return runXML(fallback, context: &context)
        }
        var properties = styleRunProperties(context.openingRunStyle)
        if let language = context.language { properties += "<w:lang w:val=\"\(xmlAttribute(language))\"/>" }
        if run.bold { properties += "<w:b/>" }
        if run.italic { properties += "<w:i/>" }
        if run.underline { properties += "<w:u w:val=\"single\"/>" }
        if run.strikethrough { properties += "<w:strike/>" }
        if run.inlineCode { properties += "<w:rStyle w:val=\"HTMLCode\"/>" }
        let rPr = properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"
        let pieces = run.text.components(separatedBy: "\n")
        let content = pieces.enumerated().map { offset, piece in
            let breakXML = offset == 0 ? "" : "<w:br/>"
            return "\(breakXML)<w:t xml:space=\"preserve\">\(xmlText(piece))</w:t>"
        }.joined()
        let runXML = "<w:r>\(rPr)\(content)</w:r>"
        guard let target = run.hyperlink, !target.isEmpty else { return runXML }
        let id = context.hyperlinkID(for: target)
        return "<w:hyperlink r:id=\"\(id)\" w:history=\"1\">\(runXML)</w:hyperlink>"
    }

    private static func tableXML(
        _ table: WordTable,
        numberingIDs: [NumberingKey: Int],
        context: inout WritingContext
    ) throws -> String {
        let previousInTable = context.inTable
        context.inTable = true
        defer { context.inTable = previousInTable }
        let rows = try table.rows.map { row in
            let rowProperties = row.isHeader ? "<w:trPr><w:tblHeader/></w:trPr>" : ""
            let cells = try row.cells.map { blocks in
                let body = try blocks.map {
                    try blockXML($0, numberingIDs: numberingIDs, context: &context)
                }.joined()
                return "<w:tc><w:tcPr/>\(body.isEmpty ? "<w:p/>" : body)</w:tc>"
            }.joined()
            return "<w:tr>\(rowProperties)\(cells)</w:tr>"
        }.joined()
        return "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr><w:tblGrid/>\(rows)</w:tbl>"
    }

    private static func imageRunXML(
        _ image: WordImage,
        relationshipID: String,
        imageNumber: Int,
        data: Data,
        page: WordThemePage?
    ) -> String {
        let size = imageSizeEMU(data: data, page: page)
        let alternativeText = image.isDecorative ? "" : image.alternativeText ?? ""
        let description = xmlAttribute(alternativeText)
        let decorative = image.isDecorative
            ? "<a:extLst><a:ext uri=\"{C183D7F6-B498-43B3-948B-1728B52AA6E4}\"><adec:decorative val=\"1\"/></a:ext></a:extLst>"
            : ""
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(size.width)" cy="\(size.height)"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="\(imageNumber)" name="Picture \(imageNumber)" descr="\(description)">\(decorative)</wp:docPr><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(imageNumber)" name="Picture \(imageNumber)" descr="\(description)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(relationshipID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(size.width)" cy="\(size.height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    private static func imageSizeEMU(data: Data, page: WordThemePage?) -> (width: Int, height: Int) {
        let maximumWidth = ((page?.width ?? 612) - (page?.left ?? 72) - (page?.right ?? 72)) * 12_700
        let maximumHeight = ((page?.height ?? 792) - (page?.top ?? 72) - (page?.bottom ?? 72)) * 12_700
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              pixelWidth.doubleValue > 0, pixelHeight.doubleValue > 0 else {
            return (Int(min(maximumWidth, 4_572_000)), Int(min(maximumHeight, 3_048_000)))
        }
        let naturalWidth = pixelWidth.doubleValue * 9_525
        let naturalHeight = pixelHeight.doubleValue * 9_525
        let scale = min(1, maximumWidth / naturalWidth, maximumHeight / naturalHeight)
        return (max(1, Int(naturalWidth * scale)), max(1, Int(naturalHeight * scale)))
    }

    private static func localImageData(
        target: String,
        sourceDirectory: URL?
    ) -> Data? {
        guard let sourceDirectory else { return nil }
        let decoded = target.removingPercentEncoding ?? target
        guard !decoded.hasPrefix("/"), URL(string: decoded)?.scheme == nil else { return nil }
        let root = sourceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(decoded).standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPrefix) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func isDecodableImage(_ data: Data, matching ext: String) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let actualType = UTType(typeIdentifier),
              let expectedType = expectedImageType(for: ext),
              actualType.conforms(to: expectedType),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return false }
        return true
    }

    private static func expectedImageType(for ext: String) -> UTType? {
        switch ext {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "gif": return .gif
        case "bmp": return .bmp
        case "tif", "tiff": return .tiff
        case "heic": return .heic
        default: return nil
        }
    }

    private static func normalizedImageExtension(_ fileName: String) -> String? {
        let value = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch value {
        case "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "heic":
            return value
        default:
            return nil
        }
    }

    private static func imageContentType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case "heic": return "image/heic"
        default: return "image/png"
        }
    }

    private static func collectNumberingKeys(_ blocks: [WordBlock]) throws -> [NumberingKey] {
        var keys: [NumberingKey] = []
        func add(_ key: NumberingKey) {
            if !keys.contains(key) { keys.append(key) }
        }
        for block in blocks {
            try Task.checkCancellation()
            switch block {
            case .paragraph(let paragraph):
                guard let list = paragraph.list else { continue }
                switch list.kind {
                case .bullet:
                    add(NumberingKey(identifier: list.identifier, isBullet: true, start: 1))
                case .numbered(let start):
                    add(NumberingKey(
                        identifier: list.identifier,
                        isBullet: false,
                        start: start
                    ))
                }
            case .table(let table):
                for row in table.rows {
                    for cell in row.cells {
                        for key in try collectNumberingKeys(cell) { add(key) }
                    }
                }
            }
        }
        return keys
    }

    private static func numberingXML(keys: [NumberingKey]) throws -> String {
        var abstracts = ""
        var instances = ""
        for (offset, key) in keys.enumerated() {
            try Task.checkCancellation()
            let id = offset + 1
            let levels = (0...8).map { level -> String in
                let indentation = 720 + level * 360
                if key.isBullet {
                    return "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"\(indentation)\"/></w:tabs><w:ind w:left=\"\(indentation)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
                }
                return "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"\(key.start)\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%\(level + 1).\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"\(indentation)\"/></w:tabs><w:ind w:left=\"\(indentation)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
            }.joined()
            abstracts += "<w:abstractNum w:abstractNumId=\"\(id)\"><w:multiLevelType w:val=\"multilevel\"/>\(levels)</w:abstractNum>"
            instances += "<w:num w:numId=\"\(id)\"><w:abstractNumId w:val=\"\(id)\"/></w:num>"
        }
        return xmlHeader + "<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(abstracts)\(instances)</w:numbering>"
    }

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    private static func contentTypesXML(images: [ImagePart]) -> String {
        var defaults: [String: String] = [:]
        for image in images {
            defaults[URL(fileURLWithPath: image.fileName).pathExtension.lowercased()]
                = image.contentType
        }
        let imageDefaults = defaults.keys.sorted().map { ext in
            "<Default Extension=\"\(xmlAttribute(ext))\" ContentType=\"\(xmlAttribute(defaults[ext] ?? "application/octet-stream"))\"/>"
        }.joined()
        return xmlHeader + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>\(imageDefaults)<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
        """
    }

    private static let packageRelationshipsXML = xmlHeader + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
    """

    private static func corePropertiesXML(title: String, language: String) -> String {
        xmlHeader + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><dc:title>\(xmlText(title))</dc:title><dc:creator>ghostWriter</dc:creator><dc:language>\(xmlText(language))</dc:language><cp:lastModifiedBy>ghostWriter</cp:lastModifiedBy></cp:coreProperties>"
    }

    private static let appPropertiesXML = xmlHeader + """
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>ghostWriter</Application></Properties>
    """

    private struct PageContentPart {
        var name: String
        var kind: String
        var first: Bool
        var xml: String
    }

    private static func pageContentParts(_ theme: WordExportTheme?) -> [PageContentPart] {
        var parts: [PageContentPart] = []
        for (kind, value) in [("header", theme?.header), ("footer", theme?.footer)] {
            guard let value else { continue }
            let tag = kind == "header" ? "hdr" : "ftr"
            let text = value.text.map { "<w:r><w:t xml:space=\"preserve\">\(xmlText($0))</w:t></w:r>" } ?? ""
            let number = value.pageNumber == true ? "<w:fldSimple w:instr=\" PAGE \" w:dirty=\"true\"><w:r><w:t>1</w:t></w:r></w:fldSimple>" : ""
            let start = xmlHeader + "<w:\(tag) xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            let paragraph = "<w:p><w:pPr><w:jc w:val=\"\(value.alignment ?? "left")\"/></w:pPr>\(text)\(number)</w:p>"
            parts.append(PageContentPart(name: kind, kind: kind, first: false, xml: start + paragraph + "</w:\(tag)>"))
            if theme?.differentFirstPage == true {
                parts.append(PageContentPart(name: kind + "First", kind: kind, first: true, xml: start + "<w:p/></w:\(tag)>"))
            }
        }
        return parts
    }

    private static func pageXML(_ page: WordThemePage?, parts: [PageContentPart], differentFirstPage: Bool) -> String {
        func twips(_ value: Double) -> Int { Int((value * 20).rounded()) }
        let references = parts.map {
            "<w:\($0.kind)Reference w:type=\"\($0.first ? "first" : "default")\" r:id=\"rId\($0.name)\"/>"
        }.joined()
        return "<w:sectPr>\(references)<w:pgSz w:w=\"\(twips(page?.width ?? 612))\" w:h=\"\(twips(page?.height ?? 792))\"/><w:pgMar w:top=\"\(twips(page?.top ?? 72))\" w:right=\"\(twips(page?.right ?? 72))\" w:bottom=\"\(twips(page?.bottom ?? 72))\" w:left=\"\(twips(page?.left ?? 72))\" w:header=\"360\" w:footer=\"360\"/>\(differentFirstPage ? "<w:titlePg/>" : "")</w:sectPr>"
    }

    private static func styleRunProperties(_ style: WordThemeStyle?, defaultSize: Double? = nil, defaultBold: Bool = false, defaultFont: String? = nil) -> String {
        var xml = ""
        if let font = style?.font ?? defaultFont {
            xml += "<w:rFonts w:ascii=\"\(xmlAttribute(font))\" w:hAnsi=\"\(xmlAttribute(font))\" w:eastAsia=\"\(xmlAttribute(font))\" w:cs=\"\(xmlAttribute(font))\"/>"
        }
        if let bold = style?.bold ?? (defaultBold ? true : nil) { xml += "<w:b w:val=\"\(bold ? 1 : 0)\"/>" }
        if let italic = style?.italic { xml += "<w:i w:val=\"\(italic ? 1 : 0)\"/>" }
        if let color = style?.color { xml += "<w:color w:val=\"\(color.uppercased())\"/>" }
        if let size = style?.size ?? defaultSize { xml += "<w:sz w:val=\"\(Int((size * 2).rounded()))\"/>" }
        return xml
    }

    private static func styleParagraphProperties(_ style: WordThemeStyle?, defaultLeftIndent: Double? = nil) -> String {
        var xml = ""
        if let value = style?.keepWithNext { xml += "<w:keepNext w:val=\"\(value ? 1 : 0)\"/>" }
        if let value = style?.pageBreakBefore { xml += value ? "<w:pageBreakBefore/>" : "<w:pageBreakBefore w:val=\"0\"/>" }
        var spacing = ""
        if let value = style?.spaceBefore { spacing += " w:before=\"\(Int((value * 20).rounded()))\"" }
        if let value = style?.spaceAfter { spacing += " w:after=\"\(Int((value * 20).rounded()))\"" }
        if let value = style?.lineSpacing { spacing += " w:line=\"\(Int((value * 240).rounded()))\" w:lineRule=\"auto\"" }
        if !spacing.isEmpty { xml += "<w:spacing\(spacing)/>" }
        var indentation = ""
        if let value = defaultLeftIndent { indentation += " w:left=\"\(Int((value * 20).rounded()))\"" }
        if let value = style?.firstLineIndent { indentation += " w:firstLine=\"\(Int((value * 20).rounded()))\"" }
        if !indentation.isEmpty { xml += "<w:ind\(indentation)/>" }
        if let alignment = style?.alignment { xml += "<w:jc w:val=\"\(alignment == "justify" ? "both" : alignment)\"/>" }
        return xml
    }

    private static func stylesXML(language: String, theme: WordExportTheme?) -> String {
        var xml = xmlHeader + "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"22\"/><w:lang w:val=\"\(xmlAttribute(language))\"/></w:rPr></w:rPrDefault></w:docDefaults>"
        func style(_ id: String, name: String, type: String = "paragraph", value: WordThemeStyle?, pPr: String = "", defaultSize: Double? = nil, bold: Bool = false, font: String? = nil, tableProperties: String = "") -> String {
            let isNormal = id == "Normal"
            let basedOn = type == "paragraph" && !isNormal ? "<w:basedOn w:val=\"Normal\"/>" : ""
            let defaultAttribute = isNormal ? " w:default=\"1\"" : ""
            let paragraph = type == "character" ? "" : styleParagraphProperties(value, defaultLeftIndent: id == "Quote" ? 36 : nil) + pPr
            let run = styleRunProperties(value, defaultSize: defaultSize, defaultBold: bold, defaultFont: font)
            return "<w:style w:type=\"\(type)\"\(defaultAttribute) w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/>\(basedOn)\(paragraph.isEmpty ? "" : "<w:pPr>" + paragraph + "</w:pPr>")\(run.isEmpty ? "" : "<w:rPr>" + run + "</w:rPr>")\(tableProperties)</w:style>"
        }
        xml += style("Normal", name: "Normal", value: theme?.body)
        for level in 1...6 {
            let defaultSize: Double? = [1: 16.0, 2: 14.0, 3: 13.0][level]
            xml += style("Heading\(level)", name: "heading \(level)", value: theme?.headings?[String(level)], pPr: "<w:outlineLvl w:val=\"\(level - 1)\"/>", defaultSize: defaultSize, bold: true)
        }
        xml += style("Quote", name: "Quote", value: theme?.quote)
        xml += style("HTMLPreformatted", name: "HTML Preformatted", value: theme?.code, font: "Courier New")
        xml += style("HTMLCode", name: "HTML Code", type: "character", value: theme?.code, font: "Courier New")
        if let list = theme?.list { xml += style("ListParagraph", name: "List Paragraph", value: list) }
        let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:color=\"auto\"/>" }.joined()
        xml += style("TableGrid", name: "Table Grid", type: "table", value: theme?.table, tableProperties: "<w:tblPr><w:tblBorders>\(borders)</w:tblBorders></w:tblPr>")
        return xml + "</w:styles>"
    }

    private static func data(_ string: String) -> Data { Data(string.utf8) }

    private static func xmlText(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func xmlAttribute(_ string: String) -> String {
        xmlText(string)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
