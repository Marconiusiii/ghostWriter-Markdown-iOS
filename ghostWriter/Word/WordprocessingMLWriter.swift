import Foundation
import ImageIO

nonisolated enum WordprocessingMLWriter {
    private struct NumberingKey: Hashable {
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
            guard let ext = normalizedImageExtension(sourceName) else { return nil }
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
        sourceDirectory: URL? = nil
    ) throws -> Data {
        let numberingKeys = collectNumberingKeys(document.blocks)
        let numberingIDs = Dictionary(
            uniqueKeysWithValues: numberingKeys.enumerated().map { ($0.element, $0.offset + 1) }
        )
        var context = WritingContext(sourceDirectory: sourceDirectory)
        let body = try document.blocks.map {
            try blockXML($0, numberingIDs: numberingIDs, context: &context)
        }.joined()

        let hyperlinkXML = context.hyperlinks.map { relationship in
            "<Relationship Id=\"\(relationship.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(xmlAttribute(relationship.target))\" TargetMode=\"External\"/>"
        }.joined()
        let imageXML = context.images.map { image in
            "<Relationship Id=\"\(image.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(xmlAttribute(image.fileName))\"/>"
        }.joined()

        let documentXML = xmlHeader + """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" xmlns:adec="http://schemas.microsoft.com/office/drawing/2017/decorative"><w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
        """
        let documentRelationships = xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>\(hyperlinkXML)\(imageXML)</Relationships>
        """

        var entries: [String: Data] = [
            "[Content_Types].xml": data(contentTypesXML(images: context.images)),
            "_rels/.rels": data(packageRelationshipsXML),
            "docProps/core.xml": data(corePropertiesXML(title: title)),
            "docProps/app.xml": data(appPropertiesXML),
            "word/document.xml": data(documentXML),
            "word/_rels/document.xml.rels": data(documentRelationships),
            "word/styles.xml": data(stylesXML),
            "word/numbering.xml": data(numberingXML(keys: numberingKeys))
        ]
        for image in context.images {
            entries["word/media/\(image.fileName)"] = image.data
        }
        return try WordPackage.create(entries: entries)
    }

    private static func blockXML(
        _ block: WordBlock,
        numberingIDs: [NumberingKey: Int],
        context: inout WritingContext
    ) throws -> String {
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
        var properties = ""
        if let level = paragraph.headingLevel {
            properties += "<w:pStyle w:val=\"Heading\(max(1, min(6, level)))\"/>"
        } else if paragraph.isBlockQuote {
            properties += "<w:pStyle w:val=\"Quote\"/>"
        } else if paragraph.isCodeBlock {
            properties += "<w:pStyle w:val=\"CodeBlock\"/>"
        }
        if let list = paragraph.list {
            let key: NumberingKey
            switch list.kind {
            case .bullet: key = NumberingKey(isBullet: true, start: 1)
            case .numbered(let start): key = NumberingKey(isBullet: false, start: start)
            }
            if let numberID = numberingIDs[key] {
                properties += "<w:numPr><w:ilvl w:val=\"\(max(0, min(8, list.level)))\"/><w:numId w:val=\"\(numberID)\"/></w:numPr>"
            }
        }
        let pPr = properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>"
        let runs = paragraph.runs.map {
            runXML($0, context: &context)
        }.joined()
        return "<w:p>\(pPr)\(runs)</w:p>"
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
                    data: part.data
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
        var properties = ""
        if run.bold { properties += "<w:b/>" }
        if run.italic { properties += "<w:i/>" }
        if run.underline { properties += "<w:u w:val=\"single\"/>" }
        if run.strikethrough { properties += "<w:strike/>" }
        if run.inlineCode { properties += "<w:rStyle w:val=\"CodeChar\"/>" }
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
        data: Data
    ) -> String {
        let size = imageSizeEMU(data: data)
        let alternativeText = image.isDecorative ? "" : image.alternativeText ?? ""
        let description = xmlAttribute(alternativeText)
        let decorative = image.isDecorative
            ? "<a:extLst><a:ext uri=\"{C183D7F6-B498-43B3-948B-1728B52AA6E4}\"><adec:decorative val=\"1\"/></a:ext></a:extLst>"
            : ""
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(size.width)" cy="\(size.height)"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="\(imageNumber)" name="Picture \(imageNumber)" descr="\(description)">\(decorative)</wp:docPr><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(imageNumber)" name="Picture \(imageNumber)" descr="\(description)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(relationshipID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(size.width)" cy="\(size.height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    private static func imageSizeEMU(data: Data) -> (width: Int, height: Int) {
        let fallback = (width: 4_572_000, height: 3_048_000)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              pixelWidth.doubleValue > 0,
              pixelHeight.doubleValue > 0 else { return fallback }
        let maximum = 5_943_600.0
        let scale = min(1, maximum / pixelWidth.doubleValue)
        let width = max(1, Int(pixelWidth.doubleValue * scale * 9_525))
        let height = max(1, Int(pixelHeight.doubleValue * scale * 9_525))
        return (width, height)
    }

    private static func localImageData(
        target: String,
        sourceDirectory: URL?
    ) -> Data? {
        guard let sourceDirectory else { return nil }
        let decoded = target.removingPercentEncoding ?? target
        if decoded.lowercased().hasPrefix("http://")
            || decoded.lowercased().hasPrefix("https://") { return nil }
        let url: URL
        if let absolute = URL(string: decoded), absolute.isFileURL {
            url = absolute
        } else {
            url = sourceDirectory.appendingPathComponent(decoded).standardizedFileURL
        }
        return try? Data(contentsOf: url)
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

    private static func collectNumberingKeys(_ blocks: [WordBlock]) -> [NumberingKey] {
        var keys: [NumberingKey] = []
        func add(_ key: NumberingKey) {
            if !keys.contains(key) { keys.append(key) }
        }
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                guard let list = paragraph.list else { continue }
                switch list.kind {
                case .bullet: add(NumberingKey(isBullet: true, start: 1))
                case .numbered(let start): add(NumberingKey(isBullet: false, start: start))
                }
            case .table(let table):
                for row in table.rows {
                    for cell in row.cells {
                        for key in collectNumberingKeys(cell) { add(key) }
                    }
                }
            }
        }
        return keys
    }

    private static func numberingXML(keys: [NumberingKey]) -> String {
        var abstracts = ""
        var instances = ""
        for (offset, key) in keys.enumerated() {
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

    private static func corePropertiesXML(title: String) -> String {
        xmlHeader + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><dc:title>\(xmlText(title))</dc:title><dc:creator>ghostWriter</dc:creator><cp:lastModifiedBy>ghostWriter</cp:lastModifiedBy></cp:coreProperties>"
    }

    private static let appPropertiesXML = xmlHeader + """
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>ghostWriter</Application></Properties>
    """

    private static let stylesXML = xmlHeader + """
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="3"/></w:pPr><w:rPr><w:b/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="4"/></w:pPr><w:rPr><w:b/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="5"/></w:pPr><w:rPr><w:b/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr></w:style><w:style w:type="paragraph" w:styleId="CodeBlock"><w:name w:val="Code Block"/><w:basedOn w:val="Normal"/><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/></w:rPr></w:style><w:style w:type="character" w:styleId="CodeChar"><w:name w:val="Code Character"/><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/></w:rPr></w:style><w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:color="auto"/><w:left w:val="single" w:sz="4" w:color="auto"/><w:bottom w:val="single" w:sz="4" w:color="auto"/><w:right w:val="single" w:sz="4" w:color="auto"/><w:insideH w:val="single" w:sz="4" w:color="auto"/><w:insideV w:val="single" w:sz="4" w:color="auto"/></w:tblBorders></w:tblPr></w:style></w:styles>
    """

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
