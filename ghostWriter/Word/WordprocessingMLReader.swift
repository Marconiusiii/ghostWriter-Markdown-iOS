import Foundation

nonisolated enum WordprocessingMLReader {
    private struct Style {
        var name: String
        var basedOn: String?
        var outlineLevel: Int?
        var numberingID: String?
        var numberingLevel: Int?
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
        let relationships = try parseRelationships(
            entries["word/_rels/document.xml.rels"]
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
        relationships: [String: String]
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
        relationships: [String: String]
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
            relationships: relationships,
            inheritedCode: paragraph.isCodeBlock
        )
        return paragraph
    }

    private static func parseInlineNodes(
        _ nodes: [WordXMLNode],
        hyperlink: String?,
        relationships: [String: String],
        inheritedCode: Bool
    ) -> [WordRun] {
        var result: [WordRun] = []
        for node in nodes {
            switch node.name {
            case "r":
                let properties = node.child("rPr")
                let runStyle = properties?.child("rStyle")?.attribute("val")?.lowercased() ?? ""
                var text = ""
                for child in node.children where child.name != "rPr" {
                    switch child.name {
                    case "t", "instrText": text += child.text
                    case "tab": text += "\t"
                    case "br", "cr": text += "\n"
                    case "footnoteReference":
                        if let id = child.attribute("id") { text += "[^\(id)]" }
                    case "endnoteReference":
                        if let id = child.attribute("id") { text += "[^endnote-\(id)]" }
                    case "drawing", "pict", "object":
                        let description = child.descendants(named: "docPr").first?.attribute("descr")
                            ?? child.descendants(named: "docPr").first?.attribute("title")
                            ?? "Image"
                        text += description == "Image" ? "[Image]" : "[Image: \(description)]"
                    default: break
                    }
                }
                guard !text.isEmpty else { continue }
                result.append(
                    WordRun(
                        text: text,
                        bold: enabled(properties?.child("b")),
                        italic: enabled(properties?.child("i")),
                        strikethrough: enabled(properties?.child("strike")),
                        inlineCode: inheritedCode || runStyle.contains("code"),
                        hyperlink: hyperlink
                    )
                )
            case "hyperlink":
                let relationshipID = node.attribute("id")
                let anchor = node.attribute("anchor")
                let destination = relationshipID.flatMap { relationships[$0] }
                    ?? anchor.map { "#\($0)" }
                result += parseInlineNodes(
                    node.children,
                    hyperlink: destination,
                    relationships: relationships,
                    inheritedCode: inheritedCode
                )
            case "del":
                continue
            case "drawing", "pict", "object":
                let description = node.descendants(named: "docPr").first?.attribute("descr")
                    ?? node.descendants(named: "docPr").first?.attribute("title")
                    ?? "Image"
                result.append(WordRun(text: description == "Image" ? "[Image]" : "[Image: \(description)]"))
            default:
                result += parseInlineNodes(
                    node.children,
                    hyperlink: hyperlink,
                    relationships: relationships,
                    inheritedCode: inheritedCode
                )
            }
        }
        return mergeAdjacentRuns(result)
    }

    private static func parseTable(
        _ node: WordXMLNode,
        styles: [String: Style],
        numbering: [String: [Int: NumberLevel]],
        relationships: [String: String]
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
                numberingLevel: node.child("pPr")?.child("numPr")?.child("ilvl")?.attribute("val").flatMap(Int.init)
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
                numberingLevel: nil
            )
        }
        var visited: Set<String> = [id]
        var parent = resolved.basedOn
        while let parentID = parent, !visited.contains(parentID), let base = styles[parentID] {
            visited.insert(parentID)
            if resolved.outlineLevel == nil { resolved.outlineLevel = base.outlineLevel }
            if resolved.numberingID == nil { resolved.numberingID = base.numberingID }
            if resolved.numberingLevel == nil { resolved.numberingLevel = base.numberingLevel }
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

    private static func parseRelationships(_ data: Data?) throws -> [String: String] {
        guard let data else { return [:] }
        let root = try WordXMLTreeParser.parse(data, partName: "relationships")
        return Dictionary(uniqueKeysWithValues: root.descendants(named: "Relationship").compactMap {
            guard let id = $0.attribute("Id"), let target = $0.attribute("Target") else { return nil }
            return (id, target)
        })
    }

    private static func parseNotes(
        _ data: Data?,
        styles: [String: Style],
        numbering: [String: [Int: NumberLevel]],
        relationships: [String: String]
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

    private static func enabled(_ node: WordXMLNode?) -> Bool {
        guard let node else { return false }
        let value = node.attribute("val")?.lowercased()
        return value != "0" && value != "false" && value != "off"
    }

    private static func mergeAdjacentRuns(_ runs: [WordRun]) -> [WordRun] {
        var result: [WordRun] = []
        for run in runs {
            if var last = result.last,
               last.bold == run.bold,
               last.italic == run.italic,
               last.strikethrough == run.strikethrough,
               last.inlineCode == run.inlineCode,
               last.hyperlink == run.hyperlink {
                last.text += run.text
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        return result
    }
}
