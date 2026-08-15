import Foundation

nonisolated enum WordprocessingMLReader {
    private struct Relationship {
        var target: String
        var type: String
        var isExternal: Bool
        var data: Data?

        var isImage: Bool { type.hasSuffix("/image") }
        var isHyperlink: Bool { type.hasSuffix("/hyperlink") }
    }

    private struct Style {
        var name: String
        var basedOn: String?
        var outlineLevel: Int?
        var numberingID: String?
        var numberingLevel: Int?
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
        var strikethrough: Bool?
    }

    private struct NumberLevel {
        var format: String
        var start: Int
        var paragraphStyleID: String?
    }

    private struct AbstractNumbering {
        var levels: [Int: NumberLevel]
        var numberingStyleLink: String?
        var styleLink: String?
    }

    static func read(data: Data) throws -> WordDocumentModel {
        let paths: Set<String> = [
            "word/document.xml",
            "word/styles.xml",
            "word/numbering.xml",
            "word/_rels/document.xml.rels",
            "word/footnotes.xml",
            "word/endnotes.xml"
        ]
        let entries = try WordPackage.entries(from: data, paths: paths)
        guard let documentData = entries["word/document.xml"] else {
            throw WordConversionError.missingDocument
        }

        let styles = try parseStyles(entries["word/styles.xml"])
        let numbering = try parseNumbering(
            entries["word/numbering.xml"],
            styles: styles
        )
        let mediaEntries = try WordPackage.entries(from: data, withPrefix: "word/media/")
        let relationships = try parseRelationships(
            entries["word/_rels/document.xml.rels"],
            packageEntries: mediaEntries
        )
        let root = try WordXMLTreeParser.parse(documentData, partName: "document content")
        guard let body = root.descendants(named: "body").first else {
            throw WordConversionError.missingDocument
        }

        var model = WordDocumentModel(
            blocks: parseBlocks(
                body.children,
                styles: styles,
                numbering: numbering,
                relationships: relationships
            )
        )
        model.footnotes = try parseNotes(
            entries["word/footnotes.xml"],
            styles: styles,
            numbering: numbering,
            relationships: relationships
        )
        let endnotes = try parseNotes(
            entries["word/endnotes.xml"],
            styles: styles,
            numbering: numbering,
            relationships: relationships
        )
        for (key, value) in endnotes {
            model.footnotes["endnote-\(key)"] = value
        }
        return model
    }

    private static func parseBlocks(
        _ nodes: [WordXMLNode],
        styles: [String: Style],
        numbering: [String: [Int: NumberLevel]],
        relationships: [String: Relationship]
    ) -> [WordBlock] {
        var blocks: [WordBlock] = []
        for node in nodes {
            switch node.name {
            case "p":
                blocks.append(.paragraph(
                    parseParagraph(
                        node,
                        styles: styles,
                        numbering: numbering,
                        relationships: relationships
                    )
                ))
            case "tbl":
                blocks.append(.table(
                    parseTable(
                        node,
                        styles: styles,
                        numbering: numbering,
                        relationships: relationships
                    )
                ))
            case "sdt", "customXml", "ins":
                blocks += parseBlocks(
                    node.children,
                    styles: styles,
                    numbering: numbering,
                    relationships: relationships
                )
            default:
                continue
            }
        }
        return blocks
    }

    private static func parseParagraph(
        _ node: WordXMLNode,
        styles: [String: Style],
        numbering: [String: [Int: NumberLevel]],
        relationships: [String: Relationship]
    ) -> WordParagraph {
        let properties = node.child("pPr")
        let styleID = properties?.child("pStyle")?.attribute("val")
        let resolvedStyle = resolveStyle(styleID, styles: styles)
        var paragraph = WordParagraph(styleID: styleID)
        paragraph.headingLevel = headingLevel(for: resolvedStyle)
        let normalizedStyle = resolvedStyle.name.lowercased()
        paragraph.isBlockQuote = normalizedStyle.contains("quote")
        paragraph.isCodeBlock = normalizedStyle.contains("code")
            || normalizedStyle.contains("preformatted")

        let directNumbering = properties?.child("numPr")
        let directNumberingID = directNumbering?.child("numId")?.attribute("val")
        let numID = directNumberingID ?? resolvedStyle.numberingID
        if let numID, numID != "0" {
            let level: Int
            if directNumberingID != nil {
                level = Int(directNumbering?.child("ilvl")?.attribute("val") ?? "0") ?? 0
            } else {
                level = styleNumberingLevel(
                    styleID: styleID,
                    fallback: resolvedStyle.numberingLevel,
                    levels: numbering[numID] ?? [:],
                    styles: styles
                )
            }
            let definition = numbering[numID]?[level]
            if definition?.format == "bullet" {
                paragraph.list = WordListReference(identifier: numID, level: level, kind: .bullet)
            } else {
                paragraph.list = WordListReference(
                    identifier: numID,
                    level: level,
                    kind: .numbered(start: definition?.start ?? 1)
                )
            }
        }

        paragraph.runs = parseInlineNodes(
            node.children.filter { $0.name != "pPr" },
            hyperlink: nil,
            styles: styles,
            relationships: relationships,
            inheritedCode: paragraph.isCodeBlock
        )
        return paragraph
    }

    private static func parseInlineNodes(
        _ nodes: [WordXMLNode],
        hyperlink: String?,
        styles: [String: Style],
        relationships: [String: Relationship],
        inheritedCode: Bool
    ) -> [WordRun] {
        var result: [WordRun] = []
        for node in nodes {
            switch node.name {
            case "r":
                let properties = node.child("rPr")
                let runStyleID = properties?.child("rStyle")?.attribute("val")
                let runStyle = runStyleID?.lowercased() ?? ""
                let resolvedRunStyle = resolveStyle(runStyleID, styles: styles)
                var text = ""
                let template = WordRun(
                    bold: runProperty(
                        properties?.child("b"),
                        alternate: properties?.child("bCs"),
                        inherited: resolvedRunStyle.bold
                    ),
                    italic: runProperty(
                        properties?.child("i"),
                        alternate: properties?.child("iCs"),
                        inherited: resolvedRunStyle.italic
                    ),
                    underline: runProperty(
                        properties?.child("u"),
                        inherited: resolvedRunStyle.underline,
                        disabledValue: "none"
                    ),
                    strikethrough: runProperty(
                        properties?.child("strike"),
                        alternate: properties?.child("dstrike"),
                        inherited: resolvedRunStyle.strikethrough
                    ),
                    inlineCode: inheritedCode || runStyle.contains("code"),
                    hyperlink: hyperlink
                )
                func appendText(_ value: String) {
                    guard !value.isEmpty else { return }
                    var run = template
                    run.text = value
                    result.append(run)
                }
                func flushText() {
                    appendText(text)
                    text = ""
                }
                for child in node.children where child.name != "rPr" {
                    switch child.name {
                    case "t", "instrText": text += child.text
                    case "tab": text += "\t"
                    case "br", "cr":
                        flushText()
                        appendText("\n")
                    case "footnoteReference":
                        flushText()
                        if let id = child.attribute("id") { appendText("[^\(id)]") }
                    case "endnoteReference":
                        flushText()
                        if let id = child.attribute("id") {
                            appendText("[^endnote-\(id)]")
                        }
                    case "drawing", "pict", "object":
                        flushText()
                        if let image = image(from: child, relationships: relationships) {
                            var run = template
                            run.image = image
                            result.append(run)
                        } else {
                            appendText(imagePlaceholder(from: child))
                        }
                    default: break
                    }
                }
                flushText()
            case "hyperlink":
                let relationshipID = node.attribute("id")
                let anchor = node.attribute("anchor")
                let destination = relationshipID.flatMap { id in
                    guard let relationship = relationships[id], relationship.isHyperlink else {
                        return nil
                    }
                    return relationship.target
                }
                    ?? anchor.map { "#\($0)" }
                result += parseInlineNodes(
                    node.children,
                    hyperlink: destination,
                    styles: styles,
                    relationships: relationships,
                    inheritedCode: inheritedCode
                )
            case "del":
                continue
            case "drawing", "pict", "object":
                if let image = image(from: node, relationships: relationships) {
                    result.append(WordRun(image: image))
                } else {
                    result.append(WordRun(text: imagePlaceholder(from: node)))
                }
            default:
                result += parseInlineNodes(
                    node.children,
                    hyperlink: hyperlink,
                    styles: styles,
                    relationships: relationships,
                    inheritedCode: inheritedCode
                )
            }
        }
        return mergeAdjacentRuns(result)
    }

    private static func image(
        from node: WordXMLNode,
        relationships: [String: Relationship]
    ) -> WordImage? {
        let relationshipID = node.descendants(named: "blip").first?.attribute("embed")
            ?? node.descendants(named: "blip").first?.attribute("link")
            ?? node.descendants(named: "imagedata").first?.attribute("id")
        guard let relationshipID,
              let relationship = relationships[relationshipID],
              relationship.isImage else { return nil }

        let properties = node.descendants(named: "docPr").first
            ?? node.descendants(named: "cNvPr").first
        let description = properties?.attribute("descr")?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let title = properties?.attribute("title")?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let alternativeText = [description, title]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let isDecorative = node.descendants(named: "decorative").contains {
            let value = $0.attribute("val")?.lowercased()
            return value == nil || value == "1" || value == "true" || value == "on"
        }
        let decodedName = relationship.target.removingPercentEncoding
            ?? relationship.target
        return WordImage(
            fileName: URL(fileURLWithPath: decodedName).lastPathComponent,
            data: relationship.data,
            alternativeText: alternativeText,
            isDecorative: isDecorative,
            externalTarget: relationship.isExternal ? relationship.target : nil
        )
    }

    private static func imagePlaceholder(from node: WordXMLNode) -> String {
        let properties = node.descendants(named: "docPr").first
            ?? node.descendants(named: "cNvPr").first
        let description = properties?.attribute("descr")
            ?? properties?.attribute("title")
        guard let description, !description.isEmpty else { return "[Image]" }
        return "[Image: \(description)]"
    }

    private static func parseTable(
        _ node: WordXMLNode,
        styles: [String: Style],
        numbering: [String: [Int: NumberLevel]],
        relationships: [String: Relationship]
    ) -> WordTable {
        let rows = node.children(named: "tr").map { rowNode in
            let isHeader = rowNode.child("trPr")?.child("tblHeader") != nil
            let cells = rowNode.children(named: "tc").map { cell in
                parseBlocks(
                    cell.children,
                    styles: styles,
                    numbering: numbering,
                    relationships: relationships
                )
            }
            return WordTableRow(cells: cells, isHeader: isHeader)
        }
        return WordTable(rows: rows)
    }

    private static func parseStyles(_ data: Data?) throws -> [String: Style] {
        guard let data else { return [:] }
        let root = try WordXMLTreeParser.parse(data, partName: "styles")
        var styles: [String: Style] = [:]
        for node in root.descendants(named: "style") {
            guard let id = node.attribute("styleId") else { continue }
            styles[id] = Style(
                name: node.child("name")?.attribute("val") ?? id,
                basedOn: node.child("basedOn")?.attribute("val"),
                outlineLevel: node.child("pPr")?.child("outlineLvl")?.attribute("val").flatMap(Int.init),
                numberingID: node.child("pPr")?.child("numPr")?.child("numId")?.attribute("val"),
                numberingLevel: node.child("pPr")?.child("numPr")?.child("ilvl")?.attribute("val").flatMap(Int.init),
                bold: styleProperty(
                    node.child("rPr")?.child("b"),
                    alternate: node.child("rPr")?.child("bCs")
                ),
                italic: styleProperty(
                    node.child("rPr")?.child("i"),
                    alternate: node.child("rPr")?.child("iCs")
                ),
                underline: styleProperty(
                    node.child("rPr")?.child("u"),
                    disabledValue: "none"
                ),
                strikethrough: styleProperty(
                    node.child("rPr")?.child("strike"),
                    alternate: node.child("rPr")?.child("dstrike")
                )
            )
        }
        return styles
    }

    private static func resolveStyle(_ id: String?, styles: [String: Style]) -> Style {
        guard let id, var resolved = styles[id] else {
            return Style(
                name: id ?? "",
                basedOn: nil,
                outlineLevel: nil,
                numberingID: nil,
                numberingLevel: nil,
                bold: nil,
                italic: nil,
                underline: nil,
                strikethrough: nil
            )
        }
        var visited: Set<String> = [id]
        var parent = resolved.basedOn
        while let parentID = parent, !visited.contains(parentID), let base = styles[parentID] {
            visited.insert(parentID)
            if resolved.outlineLevel == nil { resolved.outlineLevel = base.outlineLevel }
            if resolved.numberingID == nil { resolved.numberingID = base.numberingID }
            if resolved.numberingLevel == nil { resolved.numberingLevel = base.numberingLevel }
            if resolved.bold == nil { resolved.bold = base.bold }
            if resolved.italic == nil { resolved.italic = base.italic }
            if resolved.underline == nil { resolved.underline = base.underline }
            if resolved.strikethrough == nil { resolved.strikethrough = base.strikethrough }
            parent = base.basedOn
        }
        return resolved
    }

    private static func styleNumberingLevel(
        styleID: String?,
        fallback: Int?,
        levels: [Int: NumberLevel],
        styles: [String: Style]
    ) -> Int {
        var currentID = styleID
        var visited: Set<String> = []
        while let candidate = currentID, !visited.contains(candidate) {
            visited.insert(candidate)
            if let match = levels.first(where: { $0.value.paragraphStyleID == candidate }) {
                return match.key
            }
            currentID = styles[candidate]?.basedOn
        }
        return fallback ?? 0
    }

    private static func headingLevel(for style: Style) -> Int? {
        if let outline = style.outlineLevel, (0...5).contains(outline) {
            return outline + 1
        }
        let name = style.name.lowercased().replacingOccurrences(of: " ", with: "")
        guard name.hasPrefix("heading"),
              let level = Int(name.dropFirst("heading".count)),
              (1...6).contains(level) else { return nil }
        return level
    }

    private static func parseNumbering(
        _ data: Data?,
        styles: [String: Style]
    ) throws -> [String: [Int: NumberLevel]] {
        guard let data else { return [:] }
        let root = try WordXMLTreeParser.parse(data, partName: "numbering")
        var abstracts: [String: AbstractNumbering] = [:]
        for abstract in root.descendants(named: "abstractNum") {
            guard let id = abstract.attribute("abstractNumId") else { continue }
            var levels: [Int: NumberLevel] = [:]
            for level in abstract.children(named: "lvl") {
                let index = Int(level.attribute("ilvl") ?? "0") ?? 0
                levels[index] = NumberLevel(
                    format: level.child("numFmt")?.attribute("val") ?? "decimal",
                    start: Int(level.child("start")?.attribute("val") ?? "1") ?? 1,
                    paragraphStyleID: level.child("pStyle")?.attribute("val")
                )
            }
            abstracts[id] = AbstractNumbering(
                levels: levels,
                numberingStyleLink: abstract.child("numStyleLink")?.attribute("val"),
                styleLink: abstract.child("styleLink")?.attribute("val")
            )
        }

        var concreteAbstractIDs: [String: String] = [:]
        for node in root.children(named: "num") {
            guard let id = node.attribute("numId"),
                  let abstractID = node.child("abstractNumId")?.attribute("val"),
                  concreteAbstractIDs[id] == nil else { continue }
            concreteAbstractIDs[id] = abstractID
        }
        var styleLinkedAbstractIDs: [String: String] = [:]
        for (id, definition) in abstracts {
            guard let styleID = definition.styleLink,
                  styleLinkedAbstractIDs[styleID] == nil else { continue }
            styleLinkedAbstractIDs[styleID] = id
        }

        func resolvedLevels(for abstractID: String, visited: Set<String> = []) -> [Int: NumberLevel] {
            guard !visited.contains(abstractID), let abstract = abstracts[abstractID] else { return [:] }
            guard let styleID = abstract.numberingStyleLink else { return abstract.levels }
            var nextVisited = visited
            nextVisited.insert(abstractID)
            if let linkedAbstractID = styleLinkedAbstractIDs[styleID] {
                return resolvedLevels(for: linkedAbstractID, visited: nextVisited)
            }
            if let linkedNumberingID = styles[styleID]?.numberingID,
               let linkedAbstractID = concreteAbstractIDs[linkedNumberingID] {
                return resolvedLevels(for: linkedAbstractID, visited: nextVisited)
            }
            return abstract.levels
        }

        var result: [String: [Int: NumberLevel]] = [:]
        for number in root.children(named: "num") {
            guard let id = number.attribute("numId"),
                  let abstractID = number.child("abstractNumId")?.attribute("val") else { continue }
            var levels = resolvedLevels(for: abstractID)
            for override in number.children(named: "lvlOverride") {
                let index = Int(override.attribute("ilvl") ?? "0") ?? 0
                if let start = override.child("startOverride")?.attribute("val").flatMap(Int.init) {
                    var level = levels[index] ?? NumberLevel(
                        format: "decimal",
                        start: 1,
                        paragraphStyleID: nil
                    )
                    level.start = start
                    levels[index] = level
                }
                if let replacement = override.child("lvl") {
                    levels[index] = NumberLevel(
                        format: replacement.child("numFmt")?.attribute("val")
                            ?? levels[index]?.format
                            ?? "decimal",
                        start: Int(replacement.child("start")?.attribute("val") ?? "")
                            ?? levels[index]?.start
                            ?? 1,
                        paragraphStyleID: replacement.child("pStyle")?.attribute("val")
                            ?? levels[index]?.paragraphStyleID
                    )
                }
            }
            result[id] = levels
        }
        return result
    }

    private static func parseRelationships(
        _ data: Data?,
        packageEntries: [String: Data]
    ) throws -> [String: Relationship] {
        guard let data else { return [:] }
        let root = try WordXMLTreeParser.parse(data, partName: "relationships")
        return Dictionary(uniqueKeysWithValues: root.descendants(named: "Relationship").compactMap {
            guard let id = $0.attribute("Id"),
                  let target = $0.attribute("Target"),
                  let type = $0.attribute("Type") else { return nil }
            let isExternal = $0.attribute("TargetMode")?.lowercased() == "external"
            let packagePath = packagePath(forDocumentTarget: target)
            return (id, Relationship(
                target: target,
                type: type,
                isExternal: isExternal,
                data: isExternal ? nil : packageEntries[packagePath]
            ))
        })
    }

    private static func packagePath(forDocumentTarget target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        let components = ArraySlice(("word/" + target).split(separator: "/"))
        var resolved: [Substring] = []
        for component in components {
            if component == "." { continue }
            if component == ".." {
                _ = resolved.popLast()
            } else {
                resolved.append(component)
            }
        }
        return resolved.joined(separator: "/")
    }

    private static func parseNotes(
        _ data: Data?,
        styles: [String: Style],
        numbering: [String: [Int: NumberLevel]],
        relationships: [String: Relationship]
    ) throws -> [String: [WordBlock]] {
        guard let data else { return [:] }
        let root = try WordXMLTreeParser.parse(data, partName: "notes")
        var notes: [String: [WordBlock]] = [:]
        for node in root.children where node.name == "footnote" || node.name == "endnote" {
            guard let id = node.attribute("id"), Int(id).map({ $0 >= 0 }) == true else { continue }
            notes[id] = parseBlocks(
                node.children,
                styles: styles,
                numbering: numbering,
                relationships: relationships
            )
        }
        return notes
    }

    private static func styleProperty(
        _ node: WordXMLNode?,
        alternate: WordXMLNode? = nil,
        disabledValue: String? = nil
    ) -> Bool? {
        guard let property = node ?? alternate else { return nil }
        let value = property.attribute("val")?.lowercased()
        if let disabledValue, value == disabledValue { return false }
        return value != "0"
            && value != "false"
            && value != "off"
    }

    private static func runProperty(
        _ node: WordXMLNode?,
        alternate: WordXMLNode? = nil,
        inherited: Bool?,
        disabledValue: String? = nil
    ) -> Bool {
        styleProperty(node, alternate: alternate, disabledValue: disabledValue)
            ?? inherited
            ?? false
    }

    private static func mergeAdjacentRuns(_ runs: [WordRun]) -> [WordRun] {
        var result: [WordRun] = []
        for run in runs {
            if var last = result.last,
               !isFootnoteReference(last.text),
               !isFootnoteReference(run.text),
               last.bold == run.bold,
               last.italic == run.italic,
               last.underline == run.underline,
               last.strikethrough == run.strikethrough,
               last.inlineCode == run.inlineCode,
               last.hyperlink == run.hyperlink,
               last.image == nil,
               run.image == nil {
                last.text += run.text
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        return result
    }

    private static func isFootnoteReference(_ text: String) -> Bool {
        text.hasPrefix("[^") && text.hasSuffix("]")
    }
}
