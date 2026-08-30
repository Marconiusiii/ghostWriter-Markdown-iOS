import Foundation

nonisolated struct WordDocumentModel: Equatable, Sendable {
    var blocks: [WordBlock] = []
    var footnotes: [String: [WordBlock]] = [:]
}

nonisolated enum WordBlock: Equatable, Sendable {
    case paragraph(WordParagraph)
    case table(WordTable)
}

nonisolated struct WordParagraph: Equatable, Sendable {
    var runs: [WordRun] = []
    var styleID: String?
    var headingLevel: Int?
    var list: WordListReference?
    var isBlockQuote = false
    var isCodeBlock = false
}

nonisolated struct WordRun: Equatable, Sendable {
    var text = ""
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var inlineCode = false
    var hyperlink: String?
    var image: WordImage?
}

nonisolated struct WordImage: Equatable, Sendable {
    var fileName: String
    var data: Data? = nil
    var alternativeText: String? = nil
    var isDecorative = false
    var externalTarget: String? = nil
}

// Keep existing Word callers source-compatible with the shared import result.
typealias WordMarkdownImport = MarkdownDocumentImport
typealias WordImportedAsset = MarkdownImportedAsset

nonisolated struct WordListReference: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case bullet
        case numbered(start: Int)
    }

    var identifier = ""
    var level: Int
    var kind: Kind
}

nonisolated struct WordTable: Equatable, Sendable {
    var rows: [WordTableRow]
}

nonisolated struct WordTableRow: Equatable, Sendable {
    var cells: [[WordBlock]]
    var isHeader = false
}

nonisolated enum WordConversionError: LocalizedError, Equatable, Sendable {
    case invalidPackage
    case missingDocument
    case oversizedDocument
    case unsupportedEncryptedDocument
    case invalidXML(String)
    case couldNotCreateDocument

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            return String(localized: "The selected file is not a valid Word document.")
        case .missingDocument:
            return String(localized: "The Word document does not contain readable document content.")
        case .oversizedDocument:
            return String(localized: "The Word document is too large to import safely.")
        case .unsupportedEncryptedDocument:
            return String(localized: "Password-protected Word documents cannot be imported.")
        case .invalidXML(let part):
            return String(localized: "The Word document contains unreadable \(part).")
        case .couldNotCreateDocument:
            return String(localized: "The Word document could not be created.")
        }
    }
}
