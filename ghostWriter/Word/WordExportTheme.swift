import Foundation

/// A deliberately bounded JSON format. Unknown fields are errors, not silent typos.
nonisolated struct WordExportTheme: Codable, Equatable, Sendable {
    var version: Int = 1
    var body: WordThemeStyle?
    var headings: [String: WordThemeStyle]?
    var quote: WordThemeStyle?
    var code: WordThemeStyle?
    var list: WordThemeStyle?
    var table: WordThemeStyle?
    var page: WordThemePage?

    static let maximumBytes = 65_536

    static func load(from url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else {
            throw WordThemeError.invalid("The JSON style sheet must be 64 KiB or smaller.")
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WordThemeError.invalid("The JSON style sheet must contain an object.")
            }
            try checkKeys(object, allowed: ["version", "body", "headings", "quote", "code", "list", "table", "page"], path: "theme")
            let styleKeys: Set<String> = ["font", "size", "color", "bold", "italic", "spaceBefore", "spaceAfter", "lineSpacing", "alignment"]
            for name in ["body", "quote", "code", "list", "table"] where object[name] != nil {
                try checkKeys(try dictionary(object[name], path: name), allowed: styleKeys, path: name)
            }
            if let headings = object["headings"] {
                let values = try dictionary(headings, path: "headings")
                try checkKeys(values, allowed: Set((1...6).map(String.init)), path: "headings")
                for (key, value) in values {
                    try checkKeys(try dictionary(value, path: "headings.\(key)"), allowed: styleKeys, path: "headings.\(key)")
                }
            }
            if let page = object["page"] {
                try checkKeys(try dictionary(page, path: "page"), allowed: ["width", "height", "top", "right", "bottom", "left"], path: "page")
            }
            let theme = try JSONDecoder().decode(Self.self, from: data)
            guard theme.version == 1 else { throw WordThemeError.invalid("version must be 1.") }
            for (path, style) in [("body", theme.body), ("quote", theme.quote), ("code", theme.code), ("list", theme.list), ("table", theme.table)] {
                try style?.validate(path: path)
            }
            for (key, style) in theme.headings ?? [:] { try style.validate(path: "headings.\(key)") }
            try theme.page?.validate()
            return theme
        } catch let error as WordThemeError { throw error }
        catch let error as DecodingError {
            let context: DecodingError.Context
            switch error {
            case .keyNotFound(_, let value), .typeMismatch(_, let value), .valueNotFound(_, let value), .dataCorrupted(let value): context = value
            @unknown default: throw WordThemeError.invalid("Check the JSON field values and version.")
            }
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw WordThemeError.invalid("Check \(path.isEmpty ? "version and field values" : path): \(context.debugDescription)")
        } catch { throw WordThemeError.invalid("The file is not valid JSON. Check quotes, commas, and brackets.") }
    }

    private static func dictionary(_ value: Any?, path: String) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw WordThemeError.invalid("\(path) must be an object.") }
        return value
    }

    private static func checkKeys(_ values: [String: Any], allowed: Set<String>, path: String) throws {
        if let key = values.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw WordThemeError.invalid("Unknown setting: \(path).\(key).")
        }
        if let key = values.keys.sorted().first(where: { values[$0] is NSNull }) {
            throw WordThemeError.invalid("Omit \(path).\(key) instead of setting it to null.")
        }
    }
}

nonisolated struct WordThemeStyle: Codable, Equatable, Sendable {
    var font: String?
    var size: Double?
    var color: String?
    var bold: Bool?
    var italic: Bool?
    var spaceBefore: Double?
    var spaceAfter: Double?
    var lineSpacing: Double?
    var alignment: String?

    func validate(path: String) throws {
        if let font, font.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || font.count > 128 || font.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw WordThemeError.invalid("\(path).font must be a font name of 1 to 128 characters without control characters.")
        }
        if let color, color.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) == nil {
            throw WordThemeError.invalid("\(path).color must contain six hexadecimal digits, without #.")
        }
        if let alignment, !["left", "center", "right", "justify"].contains(alignment) {
            throw WordThemeError.invalid("\(path).alignment must be left, center, right, or justify.")
        }
        for (name, value, range) in [("size", size, 1.0...200.0), ("spaceBefore", spaceBefore, 0.0...720.0), ("spaceAfter", spaceAfter, 0.0...720.0), ("lineSpacing", lineSpacing, 0.5...5.0)] {
            if let value, !value.isFinite || !range.contains(value) {
                throw WordThemeError.invalid("\(path).\(name) must be between \(range.lowerBound) and \(range.upperBound).")
            }
        }
    }
}

nonisolated struct WordThemePage: Codable, Equatable, Sendable {
    var width: Double?
    var height: Double?
    var top: Double?
    var right: Double?
    var bottom: Double?
    var left: Double?

    func validate() throws {
        for (name, value, range) in [("width", width, 144.0...1584.0), ("height", height, 144.0...1584.0), ("top", top, 0.0...720.0), ("right", right, 0.0...720.0), ("bottom", bottom, 0.0...720.0), ("left", left, 0.0...720.0)] {
            if let value, !value.isFinite || !range.contains(value) {
                throw WordThemeError.invalid("page.\(name) must be between \(range.lowerBound) and \(range.upperBound) points.")
            }
        }
        guard (width ?? 612) - (left ?? 72) - (right ?? 72) >= 72,
              (height ?? 792) - (top ?? 72) - (bottom ?? 72) >= 72 else {
            throw WordThemeError.invalid("Page margins must leave at least 72 points of content width and height.")
        }
    }
}

nonisolated enum WordThemeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
