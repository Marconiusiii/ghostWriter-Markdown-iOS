import Foundation
import ZIPFoundation

/// Reads selected package parts into bounded memory; never extracts ZIP paths
/// onto disk and never follows an external relationship.
nonisolated final class PowerPointImportPackage {
    static let maximumFileSize = 512 * 1024 * 1024
    static let maximumDocumentBytes = 96 * 1024 * 1024
    static let maximumImageBytes = 96 * 1024 * 1024
    private let archive: Archive
    private var documentCache: [String: Data] = [:]
    private(set) var extractedDocumentBytes = 0
    private(set) var extractedImageBytes = 0

    /// File-backed reading keeps the ZIP on disk. The caller coordinates the
    /// entire conversion and retains security-scoped access until it finishes.
    convenience init(url: URL) throws {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.seekToEnd() <= UInt64(Self.maximumFileSize) else {
            throw PowerPointImportError.limitExceeded(.fileSize)
        }
        try handle.seek(toOffset: 0)
        try Self.checkEncryption(try handle.read(upToCount: 8) ?? Data())
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw PowerPointImportError.invalidPackage }
        try self.init(archive: archive)
    }

    /// In-memory entry point remains available for generated fixtures.
    convenience init(data: Data) throws {
        guard data.count <= Self.maximumFileSize else { throw PowerPointImportError.limitExceeded(.fileSize) }
        try Self.checkEncryption(data)
        let archive: Archive
        do { archive = try Archive(data: data, accessMode: .read) }
        catch { throw PowerPointImportError.invalidPackage }
        try self.init(archive: archive)
    }

    private static func checkEncryption(_ data: Data) throws {
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            throw PowerPointImportError.encrypted
        }
    }

    private init(archive: Archive) throws {
        self.archive = archive
        var paths: Set<String> = []
        for entry in archive {
            try Task.checkCancellation()
            guard paths.count < 4096 else { throw PowerPointImportError.limitExceeded(.packageEntries) }
            guard paths.insert(entry.path).inserted else { throw PowerPointImportError.invalidPackage }
        }
        if archive["EncryptedPackage"] != nil || archive["EncryptionInfo"] != nil {
            throw PowerPointImportError.encrypted
        }
    }

    /// Image bytes are not cached here: successful images are retained by the
    /// reader, which deduplicates them. Images cannot exhaust the text budget.
    func data(at path: String, limit: Int = 8 * 1024 * 1024, isImage: Bool = false) throws -> Data {
        try Task.checkCancellation()
        let partLimit: PowerPointImportLimit = isImage ? .imageSize : .documentPart
        if !isImage, let cached = documentCache[path] {
            guard cached.count <= limit else { throw PowerPointImportError.limitExceeded(partLimit) }
            return cached
        }
        guard let entry = archive[path], entry.type == .file else { throw PowerPointImportError.invalidPackage }
        guard entry.uncompressedSize <= limit else { throw PowerPointImportError.limitExceeded(partLimit) }
        let usedBytes = isImage ? extractedImageBytes : extractedDocumentBytes
        let maximumBytes = isImage ? Self.maximumImageBytes : Self.maximumDocumentBytes
        let totalLimit: PowerPointImportLimit = isImage ? .imageContent : .documentContent
        guard usedBytes + Int(entry.uncompressedSize) <= maximumBytes else {
            throw PowerPointImportError.limitExceeded(totalLimit)
        }
        var result = Data()
        let checksum = try archive.extract(entry) { chunk in
            try Task.checkCancellation()
            guard result.count + chunk.count <= limit else { throw PowerPointImportError.limitExceeded(partLimit) }
            guard usedBytes + result.count + chunk.count <= maximumBytes else {
                throw PowerPointImportError.limitExceeded(totalLimit)
            }
            result.append(chunk)
        }
        guard checksum == entry.checksum else { throw PowerPointImportError.invalidPackage }
        if isImage {
            extractedImageBytes += result.count
        } else {
            extractedDocumentBytes += result.count
            documentCache[path] = result
        }
        return result
    }

    func xml(at path: String) throws -> PowerPointXMLNode {
        try PowerPointXMLNode.parse(data(at: path))
    }

    func relationships(for part: String) throws -> [String: Relationship] {
        let path: String
        if part.isEmpty {
            path = "_rels/.rels"
        } else {
            let pieces = part.split(separator: "/").map(String.init)
            path = (pieces.dropLast() + ["_rels", pieces.last! + ".rels"]).joined(separator: "/")
        }
        guard archive[path] != nil else { return [:] }
        let root = try xml(at: path)
        guard root.name == "Relationships" else { throw PowerPointImportError.invalidPackage }
        var result: [String: Relationship] = [:]
        for node in root.children where node.name == "Relationship" {
            guard let id = node.attributes["Id"], let type = node.attributes["Type"],
                  let target = node.attributes["Target"], result[id] == nil else {
                throw PowerPointImportError.invalidPackage
            }
            result[id] = Relationship(type: type, target: target, external: node.attributes["TargetMode"] == "External")
        }
        return result
    }

    struct Relationship {
        let type: String
        let target: String
        let external: Bool

        func isType(_ name: String) -> Bool {
            type == "http://schemas.openxmlformats.org/officeDocument/2006/relationships/" + name
                || type == "http://purl.oclc.org/ooxml/officeDocument/relationships/" + name
        }

        func path(relativeTo part: String) throws -> String {
            guard !external else { throw PowerPointImportError.invalidPackage }
            return try PowerPointImportPackage.resolve(target, relativeTo: part)
        }
    }

    static func resolve(_ target: String, relativeTo part: String) throws -> String {
        guard let decoded = target.removingPercentEncoding, !decoded.isEmpty,
              !decoded.contains("\\"), !decoded.contains(":"), !decoded.contains("?"),
              !decoded.contains("#"), !decoded.unicodeScalars.contains(where: { $0.value < 32 }),
              !decoded.hasPrefix("//") else { throw PowerPointImportError.invalidPackage }
        var pieces = decoded.hasPrefix("/") ? [] : part.split(separator: "/").dropLast().map(String.init)
        for piece in decoded.split(separator: "/") {
            if piece == "." { continue }
            if piece == ".." {
                guard !pieces.isEmpty else { throw PowerPointImportError.invalidPackage }
                pieces.removeLast()
            } else {
                pieces.append(String(piece))
            }
        }
        guard !pieces.isEmpty else { throw PowerPointImportError.invalidPackage }
        return pieces.joined(separator: "/")
    }
}

/// Small bounded XML tree shared by presentation, slide, style and notes parts.
/// Names are local names so ordinary and strict OOXML namespace prefixes work.
nonisolated final class PowerPointXMLNode {
    let name: String
    let attributes: [String: String]
    var children: [PowerPointXMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> PowerPointXMLNode? { children.first { $0.name == name } }
    func descendants(_ name: String) -> [PowerPointXMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }
    func relationshipID(_ name: String = "id") -> String? {
        attributes.first { $0.key.hasSuffix(":" + name) }?.value
    }

    static func parse(_ data: Data) throws -> PowerPointXMLNode {
        let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        guard !decoded.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !decoded.localizedCaseInsensitiveContains("<!ENTITY") else { throw PowerPointImportError.invalidXML }
        let delegate = TreeParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.rejected, let root = delegate.root else {
            try Task.checkCancellation()
            if let limit = delegate.limit { throw PowerPointImportError.limitExceeded(limit) }
            throw PowerPointImportError.invalidXML
        }
        return root
    }

    private final class TreeParser: NSObject, XMLParserDelegate {
        var root: PowerPointXMLNode?
        var stack: [PowerPointXMLNode] = []
        var count = 0
        var textBytes = 0
        var rejected = false
        var limit: PowerPointImportLimit?

        func reject(_ parser: XMLParser) { rejected = true; parser.abortParsing() }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            count += 1
            guard !Task.isCancelled else { reject(parser); return }
            guard count <= 150_000 else { limit = .xmlElements; reject(parser); return }
            guard stack.count < 64 else { limit = .xmlDepth; reject(parser); return }
            let node = PowerPointXMLNode(name: elementName.split(separator: ":").last.map(String.init) ?? elementName, attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) {
            if !stack.isEmpty { stack.removeLast() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBytes += string.utf8.count
            guard textBytes <= 8 * 1024 * 1024 else { limit = .xmlText; reject(parser); return }
            stack.last?.text += string
        }
        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            self.parser(parser, foundCharacters: String(decoding: data, as: UTF8.self))
        }
        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName: String, value: String?) { reject(parser) }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName: String, publicID: String?, systemID: String?) { reject(parser) }
        func parser(_ parser: XMLParser, resolveExternalEntityName: String, systemID: String?) -> Data? { reject(parser); return nil }
    }
}
