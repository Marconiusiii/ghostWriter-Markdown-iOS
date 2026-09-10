import Foundation

/// Converts prose only. Each chunk retains its formatting and protected chunks
/// supply context without being edited. Quote state is local to one paragraph.
nonisolated enum SmartPunctuation {
    static func markdown(_ source: String) throws -> String {
        let document = MarkdownDocumentParser.parse(source)
        var counter = 0
        return CompilationMarkdownWriter.blocks(try blocks(document.blocks), headingCounter: &counter, includesHeadingAnchors: false) + "\n"
    }

    struct Chunk {
        var text: String
        var protected = false
    }

    static func convert(_ chunks: [Chunk]) -> [String] {
        let characters = chunks.flatMap { Array($0.text) }
        var protected = chunks.flatMap { Array(repeating: $0.protected, count: $0.text.count) }
        // Bare URLs can occur in ordinary prose, not only parsed links.
        var tokenStart = 0
        for end in 0...characters.count where end == characters.count || characters[end].isWhitespace {
            let token = String(characters[tokenStart..<end])
            if token.contains("://") || token.hasPrefix("mailto:") || token.hasPrefix("www.") {
                for index in tokenStart..<end { protected[index] = true }
            }
            tokenStart = end + 1
        }
        var output = characters
        var singleOpen = false
        var doubleOpen = false
        for index in characters.indices where !protected[index] {
            let mark = characters[index]
            guard mark == "'" || mark == "\"" || "‘’“”".contains(mark) else { continue }
            let before: Character? = index > 0 ? characters[index - 1] : nil
            let after: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if mark == "“" { doubleOpen = true; continue }
            if mark == "”" { doubleOpen = false; continue }
            if mark == "‘" { singleOpen = true; continue }
            if mark == "’" {
                if before?.isLetter != true || after?.isLetter != true { singleOpen = false }
                continue
            }
            if mark == "'" {
                if before?.isLetter == true && after?.isLetter == true {
                    output[index] = "’"; continue
                }
                let suffix = String(characters.dropFirst(index + 1).prefix(6)).lowercased()
                let decade = suffix.prefix(while: { $0.isNumber })
                let isDecade = (decade.count == 2 || decade.count == 4) && suffix.dropFirst(decade.count).first == "s"
                let leadingElision = before?.isLetter != true && before?.isNumber != true
                    && (isDecade || ["tis", "twas", "twere", "em", "cause"].contains { word in
                        suffix.hasPrefix(word) && (suffix.count == word.count || !Array(suffix)[word.count].isLetter)
                    })
                if leadingElision { output[index] = "’"; continue }
                // A number followed by a mark may be a measurement. Keep it
                // literal unless it closes an already-open quotation.
                if before?.isNumber == true && !singleOpen { continue }
                let opens = !singleOpen && (before == nil || before!.isWhitespace || "([{—–\"“".contains(before!)) && after?.isWhitespace == false
                output[index] = opens ? "‘" : "’"
                singleOpen = opens
            } else {
                if before?.isNumber == true && !doubleOpen { continue }
                let opens = !doubleOpen && (before == nil || before!.isWhitespace || "([{—–‘".contains(before!)) && after?.isWhitespace == false
                output[index] = opens ? "“" : "”"
                doubleOpen = opens
            }
        }
        var offset = 0
        return chunks.map { chunk in
            defer { offset += chunk.text.count }
            return String(output[offset..<(offset + chunk.text.count)])
        }
    }

    static func inlines(_ values: [ExportInline]) -> [ExportInline] {
        var chunks: [Chunk] = []
        func collect(_ values: [ExportInline]) {
            for value in values {
                switch value {
                case .text(let text): chunks.append(Chunk(text: text))
                case .code(let text): chunks.append(Chunk(text: text, protected: true))
                case .emphasis(let c), .strong(let c), .strikethrough(let c), .underline(let c), .link(_, let c): collect(c)
                case .image: chunks.append(Chunk(text: "\u{FFFC}", protected: true))
                case .lineBreak: chunks.append(Chunk(text: "\n", protected: true))
                }
            }
        }
        collect(values)
        let converted = convert(chunks)
        var index = 0
        func rebuild(_ values: [ExportInline]) -> [ExportInline] {
            values.map { value in
                switch value {
                case .text:
                    defer { index += 1 }; return .text(converted[index])
                case .code, .image, .lineBreak: index += 1; return value
                case .emphasis(let c): return .emphasis(rebuild(c))
                case .strong(let c): return .strong(rebuild(c))
                case .strikethrough(let c): return .strikethrough(rebuild(c))
                case .underline(let c): return .underline(rebuild(c))
                case .link(let d, let c): return .link(destination: d, content: rebuild(c))
                }
            }
        }
        return rebuild(values)
    }

    static func blocks(_ values: [ExportBlock]) throws -> [ExportBlock] {
        try values.map { value in
            try Task.checkCancellation()
            switch value {
            case .heading(let level, let c): return .heading(level: level, content: inlines(c))
            case .paragraph(let c): return .paragraph(inlines(c))
            case .blockQuote(let c): return .blockQuote(try blocks(c))
            case .list(var list):
                list.items = try list.items.map { item in
                    var item = item
                    item.content = inlines(item.content)
                    item.children = try blocks(item.children)
                    return item
                }
                return .list(list)
            case .table(var table):
                table.headers = table.headers.map(inlines)
                table.rows = table.rows.map { $0.map(inlines) }
                return .table(table)
            case .codeBlock, .thematicBreak: return value
            }
        }
    }

    static func wordBlocks(_ values: [WordBlock]) throws -> [WordBlock] {
        try values.map { value in
            try Task.checkCancellation()
            switch value {
            case .paragraph(var paragraph):
                guard !paragraph.isCodeBlock else { return value }
                let texts = convert(paragraph.runs.map { Chunk(text: $0.text, protected: $0.inlineCode || $0.image != nil) })
                for index in paragraph.runs.indices { paragraph.runs[index].text = texts[index] }
                return .paragraph(paragraph)
            case .table(var table):
                for row in table.rows.indices {
                    table.rows[row].cells = try table.rows[row].cells.map(wordBlocks)
                }
                return .table(table)
            }
        }
    }
}
