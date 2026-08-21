//
//  ExportImageResource.swift
//  ghostWriter
//
//  Shared validation for images that leave the app inside exported files.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ExportImageResource {
    struct Resolved: Sendable {
        var data: Data
        var mediaType: String
        var fileName: String
    }

    static func resolveManagedAsset(
        source: String,
        sourceDirectory: URL?
    ) -> Resolved? {
        guard let sourceDirectory else { return nil }

        let decoded = source.removingPercentEncoding ?? source
        guard !decoded.hasPrefix("/"), URL(string: decoded)?.scheme == nil else {
            return nil
        }

        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard let assetDirectory = components.first,
              assetDirectory.hasPrefix(".ghostwriter-assets-") else {
            return nil
        }

        let root = sourceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(decoded).standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"

        guard url.path.hasPrefix(rootPrefix),
              let mediaType = mediaType(for: url.pathExtension),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              hasValidImageData(data, mediaType: mediaType) else {
            return nil
        }

        return Resolved(
            data: data,
            mediaType: mediaType,
            fileName: url.lastPathComponent
        )
    }

    static func mediaType(for pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        default: return nil
        }
    }

    static func hasValidImageData(_ data: Data, mediaType: String) -> Bool {
        switch mediaType {
        case "image/jpeg":
            return isDecodableRaster(data, expectedType: .jpeg)
        case "image/png":
            return isDecodableRaster(data, expectedType: .png)
        case "image/svg+xml":
            return isSafeSVG(data)
        default:
            return false
        }
    }

    /// SVG is executable XML, so exports accept only self-contained graphics
    /// without scripts, active content, animation, or external references.
    static func isSafeSVG(_ data: Data) -> Bool {
        let validator = SafeSVGValidator()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = validator
        return parser.parse() && validator.isSafe && validator.sawSVGRoot
    }

    private static func isDecodableRaster(
        _ data: Data,
        expectedType: UTType
    ) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) as String?,
              let actualType = UTType(identifier),
              actualType.conforms(to: expectedType),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            return false
        }
        return true
    }
}

nonisolated private final class SafeSVGValidator: NSObject, XMLParserDelegate {
    private static let forbiddenElements: Set<String> = [
        "script", "foreignobject", "iframe", "object", "embed", "audio",
        "video", "form", "input", "button", "animate", "animatemotion",
        "animatetransform", "set"
    ]

    private(set) var isSafe = true
    private(set) var sawSVGRoot = false
    private var sawRootElement = false
    private var insideStyle = false
    private var styleText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let element = elementName.lowercased()
        if !sawRootElement {
            sawRootElement = true
            sawSVGRoot = element == "svg"
        }
        if Self.forbiddenElements.contains(element) { isSafe = false }
        if element == "style" {
            insideStyle = true
            styleText = ""
        }

        for (rawName, rawValue) in attributeDict {
            let name = rawName.lowercased()
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if name.hasPrefix("on") { isSafe = false }
            if name == "style", containsExternalCSS(value) { isSafe = false }
            if name == "href" || name == "xlink:href" || name == "src" {
                guard value.isEmpty || value.hasPrefix("#") else {
                    isSafe = false
                    continue
                }
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "style" {
            if containsExternalCSS(styleText.lowercased()) { isSafe = false }
            insideStyle = false
            styleText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideStyle else { return }
        styleText += string
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        isSafe = false
    }

    private func containsExternalCSS(_ value: String) -> Bool {
        // CSS escapes can disguise `url` or `@import` from a literal scanner.
        // Attached SVGs do not need escaped CSS identifiers, so reject them
        // instead of risking an external request hidden behind an escape.
        if value.contains("@import") || value.contains("\\") { return true }

        var searchStart = value.startIndex
        while let opening = value.range(
            of: "url(",
            options: .caseInsensitive,
            range: searchStart..<value.endIndex
        ) {
            guard let closing = value[opening.upperBound...].firstIndex(of: ")") else {
                return true
            }

            var reference = value[opening.upperBound..<closing]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if reference.count >= 2,
               let first = reference.first,
               let last = reference.last,
               (first == "\"" && last == "\"")
                    || (first == "'" && last == "'") {
                reference = String(reference.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Fragment references point to definitions inside this same SVG,
            // such as clip paths, masks, gradients, and filters. Anything else
            // could load content from outside the attached file.
            guard reference.count > 1, reference.hasPrefix("#") else {
                return true
            }
            searchStart = value.index(after: closing)
        }

        return false
    }
}
