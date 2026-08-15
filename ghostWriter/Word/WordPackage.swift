import Foundation
import ZIPFoundation

nonisolated enum WordPackage {
    static let maximumEntrySize: UInt32 = 32 * 1024 * 1024
    static let maximumTotalSize: UInt64 = 96 * 1024 * 1024

    static func entries(from data: Data, paths: Set<String>) throws -> [String: Data] {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw WordConversionError.invalidPackage
        }

        if archive["EncryptedPackage"] != nil || archive["EncryptionInfo"] != nil {
            throw WordConversionError.unsupportedEncryptedDocument
        }

        var total: UInt64 = 0
        var result: [String: Data] = [:]
        for path in paths {
            guard let entry = archive[path] else { continue }
            guard entry.uncompressedSize <= maximumEntrySize else {
                throw WordConversionError.oversizedDocument
            }
            total += UInt64(entry.uncompressedSize)
            guard total <= maximumTotalSize else {
                throw WordConversionError.oversizedDocument
            }

            var contents = Data()
            contents.reserveCapacity(Int(entry.uncompressedSize))
            _ = try archive.extract(entry) { chunk in
                contents.append(chunk)
            }
            result[path] = contents
        }
        return result
    }

    static func create(entries: [String: Data]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for path in entries.keys.sorted() {
            guard let data = entries[path] else { continue }
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    return data.subdata(in: start..<(start + size))
                }
            )
        }
        guard let data = archive.data else {
            throw WordConversionError.couldNotCreateDocument
        }
        return data
    }
}

nonisolated final class WordXMLNode: @unchecked Sendable {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [WordXMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> WordXMLNode? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [WordXMLNode] {
        children.filter { $0.name == name }
    }

    func descendants(named name: String) -> [WordXMLNode] {
        children.flatMap { child in
            (child.name == name ? [child] : []) + child.descendants(named: name)
        }
    }

    func attribute(_ localName: String) -> String? {
        attributes[localName]
            ?? attributes.first { $0.key.split(separator: ":").last == Substring(localName) }?.value
    }
}

nonisolated final class WordXMLTreeParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var stack: [WordXMLNode] = []
    private var root: WordXMLNode?
    private var parseError: Error?

    static func parse(_ data: Data, partName: String) throws -> WordXMLNode {
        let delegate = WordXMLTreeParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.parseError == nil, let root = delegate.root else {
            throw WordConversionError.invalidXML(partName)
        }
        return root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = WordXMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}
