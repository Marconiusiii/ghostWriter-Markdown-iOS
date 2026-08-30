import Foundation
import ImageIO

nonisolated struct PowerPointImportedSlide {
    var title: [WordRun]
    var isTitleSlide: Bool
    var blocks: [WordBlock]
    var notes: [WordBlock]
}

nonisolated struct PowerPointImportedPresentation {
    var slides: [PowerPointImportedSlide] = []
    var assets: [MarkdownImportedAsset] = []
    var imagesNeedingAlternativeText = 0
    var notices: [String] = []
}

/// Reads slide order from presentation relationships and objects in stored
/// shape-tree order. Visual coordinates are not a reliable reading-order rule.
nonisolated final class PowerPointDocumentReader {
    private typealias Node = PowerPointXMLNode
    private typealias Relationship = PowerPointImportPackage.Relationship
    private let package: PowerPointImportPackage
    private let options: PowerPointImportOptions
    private let assetDirectory: String
    private var result = PowerPointImportedPresentation()
    private var extractedImages: [String: String] = [:]
    private var skippedImages = 0
    private var unsupportedObjects = 0
    private var mergedTables = 0
    private var linkedSlides = 0
    private var unavailableNotes = 0
    private var defaultTextStyle: Node?
    private var textGroup = 0

    init(data: Data, options: PowerPointImportOptions, assetDirectory: String) throws {
        package = try PowerPointImportPackage(data: data)
        self.options = options
        self.assetDirectory = assetDirectory
    }

    func read() throws -> PowerPointImportedPresentation {
        let rootRelationships = try package.relationships(for: "")
        guard let office = rootRelationships.values.first(where: { $0.isType("officeDocument") }) else {
            throw PowerPointImportError.invalidPackage
        }
        let presentationPath = try office.path(relativeTo: "")
        let presentation = try package.xml(at: presentationPath)
        guard presentation.name == "presentation",
              let slideList = presentation.child("sldIdLst") else { throw PowerPointImportError.invalidPackage }
        defaultTextStyle = presentation.child("defaultTextStyle")
        let relationships = try package.relationships(for: presentationPath)
        let slides = slideList.children.filter { $0.name == "sldId" }
        guard slides.count <= 500 else { throw PowerPointImportError.oversized }
        for (index, item) in slides.enumerated() {
            try Task.checkCancellation()
            guard let id = item.relationshipID(), let relation = relationships[id], relation.isType("slide") else {
                throw PowerPointImportError.invalidPackage
            }
            let path = try relation.path(relativeTo: presentationPath)
            let slide = try package.xml(at: path)
            guard slide.name == "sld" else { throw PowerPointImportError.invalidPackage }
            if !options.hiddenSlides, Self.isFalse(slide.attributes["show"]) { continue }
            let slideRels = try package.relationships(for: path)
            var layout: Node?
            var master: Node?
            var layoutPath = ""
            var masterPath = ""
            if let relationship = slideRels.values.first(where: { $0.isType("slideLayout") }) {
                layoutPath = try relationship.path(relativeTo: path)
                layout = try package.xml(at: layoutPath)
                let layoutRels = try package.relationships(for: layoutPath)
                if let relationship = layoutRels.values.first(where: { $0.isType("slideMaster") }) {
                    masterPath = try relationship.path(relativeTo: layoutPath)
                    master = try package.xml(at: masterPath)
                }
            }
            let shapes = Self.shapes(in: slide)
            let layoutShapes = layout.map(Self.shapes) ?? []
            let masterShapes = master.map(Self.shapes) ?? []
            let titleShape = shapes.first { shape in
                let type = Self.placeholderType(shape, inheritedFrom: layoutShapes)
                return type == "title" || type == "ctrTitle"
            }
            var title = titleShape.map { shape in
                textParagraphs(shape, path: path, relationships: slideRels,
                               inherited: Self.inheritedShapes(shape, layout: layoutShapes, master: masterShapes),
                               masterStyle: master?.child("txStyles")?.child("titleStyle"))
                    .enumerated().flatMap { index, paragraph in
                        (index == 0 ? [] : [WordRun(text: " ")]) + paragraph.runs
                    }
            } ?? []
            for i in title.indices {
                title[i].text = title[i].text.components(separatedBy: .newlines).joined(separator: " ")
            }
            if title.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = [WordRun(text: "Slide \(index + 1)")]
            }
            var blocks: [WordBlock] = []
            for shape in shapes where shape !== titleShape {
                let inherited = Self.inheritedShapes(shape, layout: layoutShapes, master: masterShapes)
                blocks += try content(shape, path: path, relationships: slideRels, inherited: inherited,
                                      master: master, inNotes: false)
            }
            // Only opted-in special placeholders are inherited as actual content.
            // Do not copy master prompts, logos, or background objects into slides.
            var present = Set(shapes.compactMap { Self.placeholderType($0, inheritedFrom: layoutShapes) })
            for (templateShapes, templatePath) in [(layoutShapes, layoutPath), (masterShapes, masterPath)] {
                for shape in templateShapes {
                    guard let type = Self.placeholder(shape)?.attributes["type"],
                          Self.specialTypes.contains(type), !present.contains(type), includes(type),
                          !templatePath.isEmpty else { continue }
                    present.insert(type)
                    blocks += try content(shape, path: templatePath,
                                          relationships: package.relationships(for: templatePath),
                                          inherited: [], master: nil, inNotes: false)
                }
            }
            var notes: [WordBlock] = []
            if options.speakerNotes, let relation = slideRels.values.first(where: { $0.isType("notesSlide") }) {
                do {
                    let notesPath = try relation.path(relativeTo: path)
                    let notesRoot = try package.xml(at: notesPath)
                    guard notesRoot.name == "notes" else { throw PowerPointImportError.invalidXML }
                    let notesRels = try package.relationships(for: notesPath)
                    for shape in Self.shapes(in: notesRoot) {
                        if Self.placeholder(shape)?.attributes["type"] == "sldImg" { continue }
                        notes += try content(shape, path: notesPath, relationships: notesRels,
                                             inherited: [], master: nil, inNotes: true)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { unavailableNotes += 1 }
            }
            result.slides.append(PowerPointImportedSlide(
                title: title,
                isTitleSlide: index == 0 && (layout?.attributes["type"] == "title"
                    || titleShape.flatMap { Self.placeholderType($0, inheritedFrom: layoutShapes) } == "ctrTitle"),
                blocks: blocks, notes: notes
            ))
        }
        guard !result.slides.isEmpty else { throw PowerPointImportError.noSlides }
        if skippedImages > 0 { result.notices.append(String(localized: "\(skippedImages) PowerPoint images could not be included. Available descriptions were kept.")) }
        if unsupportedObjects > 0 { result.notices.append(String(localized: "\(unsupportedObjects) PowerPoint objects were not converted. Available descriptions were kept.")) }
        if mergedTables > 0 { result.notices.append(String(localized: "\(mergedTables) merged PowerPoint tables were imported as labeled text rows.")) }
        if linkedSlides > 0 { result.notices.append(String(localized: "\(linkedSlides) internal slide links were imported as plain text.")) }
        if unavailableNotes > 0 { result.notices.append(String(localized: "Speaker notes could not be read on \(unavailableNotes) slides.")) }
        return result
    }

    private static let specialTypes: Set<String> = ["sldNum", "dt", "ftr", "hdr"]
    private func includes(_ type: String) -> Bool {
        switch type {
        case "sldNum": return options.slideNumbers
        case "dt": return options.dates
        case "ftr", "hdr": return options.footers
        default: return true
        }
    }

    private static func isFalse(_ value: String?) -> Bool { value == "0" || value == "false" }
    private static func isTrue(_ value: String?) -> Bool { value == "1" || value == "true" }
    private static func placeholder(_ shape: Node) -> Node? {
        shape.children.first { $0.name.hasPrefix("nv") }?.child("nvPr")?.child("ph")
    }
    private static func placeholderType(_ shape: Node, inheritedFrom layout: [Node]) -> String? {
        guard let ph = placeholder(shape) else { return nil }
        if let type = ph.attributes["type"] { return type }
        return layout.first { placeholder($0)?.attributes["idx", default: "0"] == ph.attributes["idx", default: "0"] }
            .flatMap(placeholder)?.attributes["type"] ?? "obj"
    }
    private static func inheritedShapes(_ shape: Node, layout: [Node], master: [Node]) -> [Node] {
        guard let ph = placeholder(shape) else { return [] }
        let layoutShape = layout.first { placeholder($0)?.attributes["idx", default: "0"] == ph.attributes["idx", default: "0"] }
        let type = placeholderType(shape, inheritedFrom: layout) ?? "obj"
        let masterType = type == "ctrTitle" ? "title" : type == "obj" ? "body" : type
        let masterShape = master.first { placeholder($0)?.attributes["type", default: "obj"] == masterType }
        return [layoutShape, masterShape].compactMap { $0 }
    }

    private static func shapes(in root: Node) -> [Node] {
        guard let tree = root.child("cSld")?.child("spTree") else { return [] }
        func flatten(_ node: Node) -> [Node] {
            if node.name == "grpSp" { return node.children.flatMap(flatten) }
            if node.name == "AlternateContent" {
                return (node.child("Fallback") ?? node.child("Choice"))?.children.flatMap(flatten) ?? []
            }
            return ["sp", "pic", "graphicFrame", "cxnSp", "contentPart"].contains(node.name) ? [node] : []
        }
        return tree.children.flatMap(flatten)
    }

    private func content(_ shape: Node, path: String, relationships: [String: Relationship], inherited: [Node], master: Node?, inNotes: Bool) throws -> [WordBlock] {
        let type = Self.placeholderType(shape, inheritedFrom: inherited) ?? ""
        if !includes(type) { return [] }
        let containsMedia = ["videoFile", "audioFile", "wavAudioFile", "media"].contains {
            !shape.descendants($0).isEmpty
        }
        if containsMedia {
            guard options.slideText || inNotes else { return [] }
            unsupportedObjects += 1
            return descriptionBlocks(shape, prefix: "Media")
        }
        if shape.name == "pic" { return try picture(shape, path: path, relationships: relationships) }
        if let table = shape.child("graphic")?.child("graphicData")?.child("tbl") {
            return options.tables ? tableBlocks(table, path: path, relationships: relationships) : []
        }
        if shape.name == "graphicFrame" || shape.name == "contentPart" || !shape.descendants("oleObj").isEmpty {
            guard options.slideText || inNotes else { return [] }
            unsupportedObjects += 1
            return descriptionBlocks(shape, prefix: "Object")
        }
        guard options.slideText || inNotes || Self.specialTypes.contains(type) else { return [] }
        let styleName = ["title", "ctrTitle"].contains(type) ? "titleStyle"
            : ["body", "obj"].contains(type) ? "bodyStyle" : "otherStyle"
        var blocks = textParagraphs(shape, path: path, relationships: relationships, inherited: inherited,
                                    masterStyle: master?.child("txStyles")?.child(styleName)).map(WordBlock.paragraph)
        if !shape.descendants("oMath").isEmpty || !shape.descendants("oMathPara").isEmpty {
            unsupportedObjects += 1
            blocks += descriptionBlocks(shape, prefix: "Equation")
        }
        return blocks
    }

    private func textParagraphs(_ shape: Node, path: String, relationships: [String: Relationship], inherited: [Node], masterStyle: Node?) -> [WordParagraph] {
        guard let body = shape.child("txBody") else { return [] }
        textGroup += 1
        let group = textGroup
        var output: [WordParagraph] = []
        var listSequence = 0
        var lastWasList = false
        for p in body.children where p.name == "p" {
            let direct = p.child("pPr")
            let level = min(8, max(0, Int(direct?.attributes["lvl"] ?? "0") ?? 0))
            let levelKey = "lvl\(level + 1)pPr"
            var properties = [direct, body.child("lstStyle")?.child(levelKey), body.child("lstStyle")?.child("defPPr")].compactMap { $0 }
            for inheritedShape in inherited {
                if let textBody = inheritedShape.child("txBody") {
                    properties += [textBody.child("lstStyle")?.child(levelKey), textBody.child("lstStyle")?.child("defPPr"),
                                   textBody.children.first(where: { $0.name == "p" })?.child("pPr")].compactMap { $0 }
                }
            }
            properties += [masterStyle?.child(levelKey), masterStyle?.child("defPPr"),
                           defaultTextStyle?.child(levelKey), defaultTextStyle?.child("defPPr")].compactMap { $0 }
            let defaults = properties.compactMap { $0.child("defRPr") }
            var paragraph = WordParagraph()
            for child in p.children {
                if child.name == "br" { paragraph.runs.append(WordRun(text: "\n")); continue }
                guard child.name == "r" || child.name == "fld" else { continue }
                let fieldType = child.attributes["type", default: ""].lowercased()
                if fieldType == "slidenum", !options.slideNumbers { continue }
                if fieldType.hasPrefix("datetime"), !options.dates { continue }
                var run = WordRun(text: child.child("t")?.text ?? "")
                let style = [child.child("rPr")].compactMap { $0 } + defaults
                func attribute(_ key: String) -> String? { style.compactMap { $0.attributes[key] }.first }
                if options.textFormatting {
                    run.bold = Self.isTrue(attribute("b"))
                    run.italic = Self.isTrue(attribute("i"))
                    run.underline = attribute("u").map { $0 != "none" } ?? false
                    run.strikethrough = attribute("strike").map { $0 != "noStrike" } ?? false
                }
                if options.links, let link = style.compactMap({ $0.child("hlinkClick") }).first,
                   let id = link.relationshipID(), let relation = relationships[id] {
                    if relation.isType("hyperlink"), relation.external {
                        let target = relation.target.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let url = URL(string: target), let scheme = url.scheme?.lowercased(),
                           ["https", "http", "mailto", "tel", "sms"].contains(scheme),
                           !target.unicodeScalars.contains(where: { $0.value < 32 }) {
                            run.hyperlink = target
                        }
                    } else if relation.isType("slide") { linkedSlides += 1 }
                }
                paragraph.runs.append(run)
            }
            guard !paragraph.runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let marker = properties.lazy.compactMap { node in
                node.children.first { ["buNone", "buChar", "buAutoNum", "buBlip"].contains($0.name) }
            }.first
            if let marker, marker.name != "buNone" {
                let restart = marker.attributes["startAt"].flatMap(Int.init)
                if !lastWasList || direct?.child("buAutoNum")?.attributes["startAt"] != nil { listSequence += 1 }
                let kind: WordListReference.Kind = marker.name == "buAutoNum" ? .numbered(start: max(1, restart ?? 1)) : .bullet
                paragraph.list = WordListReference(identifier: "\(path):\(group):\(listSequence)", level: level, kind: kind)
            }
            lastWasList = paragraph.list != nil
            output.append(paragraph)
        }
        return output
    }

    private func tableBlocks(_ table: Node, path: String, relationships: [String: Relationship]) -> [WordBlock] {
        let rows = table.children.filter { $0.name == "tr" }
        let hasMerges = rows.flatMap { $0.children }.contains { cell in
            ["gridSpan", "rowSpan"].contains { (Int(cell.attributes[$0] ?? "1") ?? 1) > 1 }
                || Self.isTrue(cell.attributes["hMerge"]) || Self.isTrue(cell.attributes["vMerge"])
        }
        if hasMerges { mergedTables += 1 }
        let firstRow = Self.isTrue(table.child("tblPr")?.attributes["firstRow"])
        var parsed: [WordTableRow] = []
        var fallback: [WordBlock] = []
        for (rowIndex, row) in rows.enumerated() {
            var cells: [[WordBlock]] = []
            for (column, cell) in row.children.filter({ $0.name == "tc" }).enumerated() {
                let paragraphs = textParagraphs(cell, path: path, relationships: relationships, inherited: [], masterStyle: nil)
                cells.append(paragraphs.map(WordBlock.paragraph))
                if hasMerges, !paragraphs.isEmpty {
                    var labeled = WordParagraph(runs: [WordRun(text: "Row \(rowIndex + 1), column \(column + 1): ")])
                    labeled.runs += paragraphs.enumerated().flatMap { index, p in
                        (index == 0 ? [] : [WordRun(text: "; ")]) + p.runs
                    }
                    fallback.append(.paragraph(labeled))
                }
            }
            parsed.append(WordTableRow(cells: cells, isHeader: firstRow && rowIndex == 0))
        }
        return hasMerges ? fallback : [.table(WordTable(rows: parsed))]
    }

    private func descriptionBlocks(_ shape: Node, prefix: String) -> [WordBlock] {
        let description = shape.descendants("cNvPr").first?.attributes["descr"] ?? ""
        return description.isEmpty ? [] : [.paragraph(WordParagraph(runs: [WordRun(text: "\(prefix): \(description)")]))]
    }

    private func picture(_ shape: Node, path: String, relationships: [String: Relationship]) throws -> [WordBlock] {
        guard options.images else { return [] }
        let decorative = shape.descendants("decorative").contains { Self.isTrue($0.attributes["val"]) }
        guard !decorative || options.decorativeImages else { return [] }
        let description = shape.descendants("cNvPr").first?.attributes["descr"] ?? ""
        do {
            // Prefer the ordinary raster fallback over an SVG extension when both exist.
            guard let blip = shape.child("blipFill")?.child("blip"),
                  let id = blip.relationshipID("embed"), let relation = relationships[id], relation.isType("image") else {
                throw PowerPointImportError.invalidPackage
            }
            let imagePath = try relation.path(relativeTo: path)
            let fileName: String
            if let existing = extractedImages[imagePath] {
                fileName = existing
            } else {
                guard result.assets.count < 128 else { throw PowerPointImportError.oversized }
                let bytes = try package.data(at: imagePath, limit: 10 * 1024 * 1024)
                let ext = (imagePath as NSString).pathExtension.lowercased()
                guard let mediaType = ExportImageResource.mediaType(for: ext) else { throw PowerPointImportError.invalidPackage }
                if mediaType != "image/svg+xml" {
                    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                          width.doubleValue > 0, height.doubleValue > 0,
                          width.doubleValue * height.doubleValue <= 40_000_000 else { throw PowerPointImportError.oversized }
                } else {
                    _ = try PowerPointXMLNode.parse(bytes)
                }
                guard ExportImageResource.hasValidImageData(bytes, mediaType: mediaType) else { throw PowerPointImportError.invalidPackage }
                // Generate names, rather than trusting any package filename or path.
                fileName = "image-\(result.assets.count + 1).\(ext)"
                extractedImages[imagePath] = fileName
                result.assets.append(MarkdownImportedAsset(fileName: fileName, data: bytes))
            }
            if !decorative, description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.imagesNeedingAlternativeText += 1
            }
            let image = WordImage(fileName: assetDirectory + "/" + fileName,
                                  alternativeText: description, isDecorative: decorative)
            return [.paragraph(WordParagraph(runs: [WordRun(image: image)]))]
        } catch is CancellationError { throw CancellationError() }
        catch {
            skippedImages += 1
            return decorative ? [] : descriptionBlocks(shape, prefix: "Image")
        }
    }
}
