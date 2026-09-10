import Foundation

nonisolated enum CompilationFormat: String, CaseIterable, Identifiable, Sendable {
    case word, pdf, html, markdown, plainText, epub, powerPoint, eBraille, brf
    var id: String { rawValue }
    var label: String {
        switch self {
        case .word: String(localized: "Word Document")
        case .pdf: String(localized: "PDF")
        case .html: String(localized: "HTML")
        case .markdown: String(localized: "Markdown")
        case .plainText: String(localized: "Plain Text")
        case .epub: String(localized: "EPUB")
        case .powerPoint: String(localized: "PowerPoint")
        case .eBraille: String(localized: "eBraille")
        case .brf: String(localized: "Braille Ready Format")
        }
    }
    var fileExtension: String {
        switch self {
        case .word: "docx"
        case .pdf: "pdf"
        case .html: "html"
        case .markdown: "md"
        case .plainText: "txt"
        case .epub: "epub"
        case .powerPoint: "pptx"
        case .eBraille: "ebrl"
        case .brf: "brf"
        }
    }
    var supportsHeadingOptions: Bool { self != .plainText && self != .powerPoint && self != .brf }
    var supportsPageBreaks: Bool { self == .word || self == .pdf }
}

nonisolated struct ExportCompilationSection: Equatable, Sendable {
    var start: Int
    var end: Int
    var title: String
    var language: String
}

/// Prepares independent source documents before combining their block streams.
/// Images and local linked assets receive unique relative paths in the export.
nonisolated enum CompilationDocument {
    static func prepare(sources: [WordCompilationSource], preservesHeadings: Bool, assetDirectory: URL, includesImages: Bool = true, usesSmartPunctuation: Bool = false) throws -> ExportDocument {
        var output = ExportDocument()
        let sourceURLs = sources.enumerated().compactMap { index, source -> (String, String)? in
            guard let directory = source.sourceDirectory else { return nil }
            return ((source.sourceURL ?? directory.appendingPathComponent(source.title).appendingPathExtension("md")).standardizedFileURL.resolvingSymlinksInPath().path, "#document-\(index + 1)")
        }
        let documentLinks = Dictionary(sourceURLs, uniquingKeysWith: { first, _ in first })
        var documents: [ExportDocument] = []
        var headingOffsets: [Int] = []
        var titleInsertions: [Int] = []
        var headingCount = 0
        for source in sources {
            try Task.checkCancellation()
            var document = MarkdownDocumentParser.parse(source.markdown)
            if case .heading(1, _)? = document.blocks.first { titleInsertions.append(0) }
            else {
                titleInsertions.append(1)
                document.blocks.insert(.heading(level: 1, content: [.text(source.title)]), at: 0)
            }
            if usesSmartPunctuation { document.blocks = try SmartPunctuation.blocks(document.blocks) }
            headingOffsets.append(headingCount)
            headingCount += document.headings().count
            documents.append(document)
        }
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            let document = documents[index]
            let title: String
            if case .heading(_, let content) = document.blocks[0] { title = content.plainText }
            else { title = source.title }
            var assets: [String: String] = [:]
            func destination(_ value: String, isImage: Bool) throws -> String {
                if isImage && !includesImages { return value }
                if value.hasPrefix("#heading-"), let number = Int(value.dropFirst(9)), number > 0 {
                    return "#heading-\(headingOffsets[index] + titleInsertions[index] + number)"
                }
                if value.hasPrefix("#") { return value }
                guard let root = source.sourceDirectory else { return value }
                let decoded = value.removingPercentEncoding ?? value
                guard URL(string: decoded)?.scheme == nil, !decoded.hasPrefix("/") else { return value }
                let components = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                let path = String(components[0])
                let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
                if !isImage, let link = documentLinks[url.path] {
                    if components.count == 2, components[1].hasPrefix("heading-"),
                       let heading = Int(components[1].dropFirst(8)), heading > 0,
                       let target = Int(link.dropFirst(10)), headingOffsets.indices.contains(target - 1) {
                        return "#heading-\(headingOffsets[target - 1] + titleInsertions[target - 1] + heading)"
                    }
                    return link
                }
                let safeRoot = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
                guard url.path.hasPrefix(safeRoot) else {
                    throw WordThemeError.invalid("The linked file \(value) in \(source.title) is outside its source folder.")
                }
                if let existing = assets[url.path] {
                    if !isImage, !output.compilationLinkedAssets.contains(existing) { output.compilationLinkedAssets.append(existing) }
                    return existing
                }
                try Task.checkCancellation()
                let fileExtension = url.pathExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                let relative = ".ghostwriter-assets-compilation/document-\(index + 1)/asset-\(assets.count + 1).\(fileExtension)"
                let target = assetDirectory.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                do { try FileManager.default.copyItem(at: url, to: target) }
                catch { throw WordThemeError.invalid("Could not include \(value) from \(source.title). \(error.localizedDescription)") }
                assets[url.path] = relative
                if !isImage { output.compilationLinkedAssets.append(relative) }
                return relative
            }
            func spans(_ values: [ExportInline]) throws -> [ExportInline] {
                try values.map { value in
                    try Task.checkCancellation()
                    switch value {
                    case .emphasis(let c): return .emphasis(try spans(c))
                    case .strong(let c): return .strong(try spans(c))
                    case .strikethrough(let c): return .strikethrough(try spans(c))
                    case .underline(let c): return .underline(try spans(c))
                    case .link(let target, let c): return .link(destination: try destination(target, isImage: false), content: try spans(c))
                    case .image(var image): image.source = try destination(image.source, isImage: true); return .image(image)
                    default: return value
                    }
                }
            }
            func blocks(_ values: [ExportBlock], topLevel: Bool) throws -> [ExportBlock] {
                try values.enumerated().map { offset, value in
                    try Task.checkCancellation()
                    switch value {
                    case .heading(let level, let content):
                        let keep = preservesHeadings || (index == 0 && topLevel && offset == 0)
                        return .heading(level: keep ? level : min(6, level + 1), content: try spans(content))
                    case .paragraph(let content): return .paragraph(try spans(content))
                    case .blockQuote(let c): return .blockQuote(try blocks(c, topLevel: false))
                    case .list(var list):
                        list.items = try list.items.map { item in
                            var item = item
                            item.content = try spans(item.content)
                            item.children = try blocks(item.children, topLevel: false)
                            return item
                        }
                        return .list(list)
                    case .table(var table):
                        table.headers = try table.headers.map(spans)
                        table.rows = try table.rows.map { try $0.map(spans) }
                        return .table(table)
                    default: return value
                    }
                }
            }
            let start = output.blocks.count
            output.blocks += try blocks(document.blocks, topLevel: true)
            output.compilationSections.append(ExportCompilationSection(start: start, end: output.blocks.count, title: title, language: source.language))
        }
        return output
    }
}
