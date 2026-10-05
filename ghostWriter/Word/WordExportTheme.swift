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
    var title: WordThemeStyle?
    var subtitle: WordThemeStyle?
    var thematicBreak: WordThemeBreak?
    var header: WordThemePageContent?
    var footer: WordThemePageContent?
    var differentFirstPage: Bool?
    var paragraphAfterHeading: WordThemeFollowingParagraph?
    var metadata: WordThemeMetadata?
    var tableOfContents: WordThemeContents?

    static let maximumBytes = 65_536

    static func load(from url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else {
            throw WordThemeError.invalid("The Word Stylesheet must be 64 KiB or smaller.")
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WordThemeError.invalid("The Word Stylesheet must contain an object.")
            }
            try checkKeys(object, allowed: ["version", "body", "headings", "quote", "code", "list", "table", "page", "title", "subtitle", "thematicBreak", "header", "footer", "differentFirstPage", "paragraphAfterHeading", "metadata", "tableOfContents"], path: "theme")
            let styleKeys: Set<String> = ["font", "size", "color", "bold", "italic", "spaceBefore", "spaceAfter", "lineSpacing", "alignment", "firstLineIndent", "pageBreakBefore", "pageBreakAfter", "keepWithNext", "widowControl", "keepLinesTogether"]
            for name in ["body", "quote", "code", "list", "table", "title", "subtitle"] where object[name] != nil {
                try checkKeys(try dictionary(object[name], path: name), allowed: name == "table" ? styleKeys.subtracting(["pageBreakBefore", "pageBreakAfter"]) : styleKeys, path: name)
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
            if let value = object["thematicBreak"] {
                try checkKeys(try dictionary(value, path: "thematicBreak"), allowed: ["behavior", "text"], path: "thematicBreak")
            }
            for key in ["header", "footer"] {
                if let value = object[key] {
                    try checkKeys(try dictionary(value, path: key), allowed: ["text", "pageNumber", "alignment", "template"], path: key)
                }
            }
            if let value = object["paragraphAfterHeading"] {
                try checkKeys(try dictionary(value, path: "paragraphAfterHeading"), allowed: ["headingLevels", "firstLineIndent"], path: "paragraphAfterHeading")
            }
            if let value = object["metadata"] {
                try checkKeys(try dictionary(value, path: "metadata"), allowed: ["title", "subtitle", "author"], path: "metadata")
            }
            if let value = object["tableOfContents"] {
                try checkKeys(try dictionary(value, path: "tableOfContents"), allowed: ["title", "minimumLevel", "maximumLevel", "pageNumbers", "pageBreakAfter"], path: "tableOfContents")
            }
            let theme = try JSONDecoder().decode(Self.self, from: data)
            guard theme.version == 1 else { throw WordThemeError.invalid("version must be 1.") }
            for (path, style) in [("body", theme.body), ("quote", theme.quote), ("code", theme.code), ("list", theme.list), ("table", theme.table), ("title", theme.title), ("subtitle", theme.subtitle)] {
                try style?.validate(path: path)
            }
            for (key, style) in theme.headings ?? [:] { try style.validate(path: "headings.\(key)") }
            try theme.page?.validate()
            try theme.thematicBreak?.validate()
            try theme.header?.validate(path: "header")
            try theme.footer?.validate(path: "footer")
            try theme.paragraphAfterHeading?.validate()
            try theme.metadata?.validate()
            try theme.tableOfContents?.validate()
            return theme
        } catch let error as WordThemeError { throw error }
        catch let error as DecodingError {
            let context: DecodingError.Context
            switch error {
            case .keyNotFound(_, let value), .typeMismatch(_, let value), .valueNotFound(_, let value), .dataCorrupted(let value): context = value
            @unknown default: throw WordThemeError.invalid("Check the stylesheet field values and version.")
            }
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw WordThemeError.invalid("Check \(path.isEmpty ? "version and field values" : path): \(context.debugDescription)")
        } catch { throw WordThemeError.invalid("The Word Stylesheet format is invalid. Check quotes, commas, and brackets.") }
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
    var firstLineIndent: Double?
    var pageBreakBefore: Bool?
    var pageBreakAfter: Bool?
    var keepWithNext: Bool?
    var widowControl: Bool?
    var keepLinesTogether: Bool?

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
        for (name, value, range) in [("firstLineIndent", firstLineIndent, 0.0...720.0), ("size", size, 1.0...200.0), ("spaceBefore", spaceBefore, 0.0...720.0), ("spaceAfter", spaceAfter, 0.0...720.0), ("lineSpacing", lineSpacing, 0.5...5.0)] {
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

nonisolated struct WordThemeBreak: Codable, Equatable, Sendable {
    var behavior: String
    var text: String?

    func validate() throws {
        guard ["separator", "omit", "pageBreak"].contains(behavior) else {
            throw WordThemeError.invalid("thematicBreak.behavior must be separator, omit, or pageBreak.")
        }
        if behavior == "separator" {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= 128, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw WordThemeError.invalid("thematicBreak.text must contain 1 to 128 characters on one line.")
            }
        } else if text != nil {
            throw WordThemeError.invalid("Omit thematicBreak.text unless behavior is separator.")
        }
    }
}

nonisolated struct WordThemePageContent: Codable, Equatable, Sendable {
    var text: String?
    var pageNumber: Bool?
    var alignment: String?
    var template: String?

    func validate(path: String) throws {
        if let alignment, !["left", "center", "right"].contains(alignment) {
            throw WordThemeError.invalid("\(path).alignment must be left, center, or right.")
        }
        if let text, text.count > 1024 || text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw WordThemeError.invalid("\(path).text must be at most 1024 characters on one line.")
        }
        if let template {
            guard text == nil, pageNumber == nil else {
                throw WordThemeError.invalid("Use either \(path).template or \(path).text and pageNumber, not both.")
            }
            guard template.count <= 1024, !template.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw WordThemeError.invalid("\(path).template must be at most 1024 characters on one line.")
            }
            _ = try WordThemeTemplate.parts(template, path: "\(path).template")
        }
    }
}

nonisolated struct WordThemeFollowingParagraph: Codable, Equatable, Sendable {
    var headingLevels: [Int]
    var firstLineIndent: Double

    func validate() throws {
        guard !headingLevels.isEmpty, headingLevels.allSatisfy({ (1...6).contains($0) }), Set(headingLevels).count == headingLevels.count else {
            throw WordThemeError.invalid("paragraphAfterHeading.headingLevels must contain distinct heading levels from 1 to 6.")
        }
        guard firstLineIndent.isFinite, (0...720).contains(firstLineIndent) else {
            throw WordThemeError.invalid("paragraphAfterHeading.firstLineIndent must be between 0 and 720 points.")
        }
    }
}

nonisolated struct WordThemeMetadata: Codable, Equatable, Sendable {
    var title: String?
    var subtitle: String?
    var author: String?

    func validate() throws {
        for (key, value) in [("title", title), ("subtitle", subtitle), ("author", author)] {
            if let value, value.count > 1024 || value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                throw WordThemeError.invalid("metadata.\(key) must be at most 1024 characters on one line.")
            }
        }
    }
}

/// Templates are parsed once into literal text and a closed set of fields.
/// Literal metadata never gets reparsed as a template or Word field instruction.
nonisolated enum WordThemeTemplate {
    enum Part: Equatable { case text(String), field(String) }

    static func parts(_ template: String, path: String) throws -> [Part] {
        let allowed: Set<String> = ["title", "subtitle", "author", "heading1", "heading2", "pageNumber", "date"]
        var rest = template[...]
        var result: [Part] = []
        while let open = rest.range(of: "{{") {
            let prefix = String(rest[..<open.lowerBound])
            guard !prefix.contains("}}") else { throw WordThemeError.invalid("Unmatched placeholder braces in \(path).") }
            result.append(.text(prefix))
            rest = rest[open.upperBound...]
            guard let close = rest.range(of: "}}") else { throw WordThemeError.invalid("Unclosed placeholder in \(path).") }
            let key = String(rest[..<close.lowerBound])
            guard allowed.contains(key) else { throw WordThemeError.invalid("Unsupported placeholder {{\(key)}} in \(path).") }
            result.append(.field(key))
            rest = rest[close.upperBound...]
        }
        guard !rest.contains("}}") else { throw WordThemeError.invalid("Unmatched placeholder braces in \(path).") }
        result.append(.text(String(rest)))
        return result
    }
}

nonisolated struct WordThemeContents: Codable, Equatable, Sendable {
    var title: String?
    var minimumLevel: Int?
    var maximumLevel: Int?
    var pageNumbers: Bool?
    var pageBreakAfter: Bool?

    func validate() throws {
        let lower = minimumLevel ?? 1
        let upper = maximumLevel ?? 3
        guard (1...6).contains(lower), (lower...6).contains(upper) else {
            throw WordThemeError.invalid("tableOfContents levels must be from 1 to 6, with minimumLevel no greater than maximumLevel.")
        }
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 128 || title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.union(.newlines).contains($0) }) {
            throw WordThemeError.invalid("tableOfContents.title must contain 1 to 128 characters on one line.")
        }
    }
}
