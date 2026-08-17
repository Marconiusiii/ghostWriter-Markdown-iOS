//
//  DocumentModel.swift
//  ghostWriter
//
//  A semantic model of a markdown document, shared by every export that needs
//  to know what the content *means* rather than how it looks.
//
//  MarkdownRenderer emits HTML strings as it parses, which is fine for the web
//  view but leaves nothing for other formats to reuse. MarkdownToWordConverter
//  builds a model, but a deliberately flat one — Word carries list nesting in
//  paragraph properties rather than in structure, so it never needed the tree.
//
//  Tagged PDF does need the tree. A PDF structure element for a nested list has
//  to physically contain its children, because that containment *is* the
//  reading order a screen reader follows. EPUB needs the same nesting for its
//  XHTML. So this model keeps the hierarchy that the other two throw away.
//

import Foundation

/// A parsed markdown document: a flat sequence of top-level blocks, each of
/// which may nest further.
nonisolated struct ExportDocument: Equatable, Sendable {
    var blocks: [ExportBlock] = []
}

nonisolated indirect enum ExportBlock: Equatable, Sendable {
    case heading(level: Int, content: [ExportInline])
    case paragraph([ExportInline])
    case list(ExportList)
    case table(ExportTable)
    case blockQuote([ExportBlock])
    case codeBlock(language: String?, code: String)
    case thematicBreak
}

nonisolated struct ExportList: Equatable, Sendable {
    var isOrdered: Bool
    /// The first number of an ordered list. Markdown allows a list to start at
    /// something other than one, and both PDF numbering and EPUB's `start`
    /// attribute need to honour it.
    var start: Int = 1
    var items: [ExportListItem] = []
}

nonisolated struct ExportListItem: Equatable, Sendable {
    /// The item's own text, before any nested blocks.
    var content: [ExportInline] = []
    /// Nested lists or paragraphs belonging to this item.
    var children: [ExportBlock] = []
    /// Present only for task list items. Nil means an ordinary bullet.
    var taskState: TaskState?

    nonisolated enum TaskState: Equatable, Sendable {
        case completed
        case notCompleted

        /// Spoken prefix used wherever a visual checkbox cannot be relied on.
        /// Every export states the state as words, because a glyph alone is
        /// either silent or read as a meaningless symbol.
        var spokenPrefix: String {
            switch self {
            case .completed: return "Completed:"
            case .notCompleted: return "Not completed:"
            }
        }
    }
}

nonisolated struct ExportTable: Equatable, Sendable {
    var headers: [[ExportInline]] = []
    var rows: [[[ExportInline]]] = []
    var alignments: [ExportAlignment] = []

    /// Column count taken from the widest row, so a malformed table with a
    /// short row still produces a rectangular grid rather than dropping cells.
    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    func alignment(forColumn column: Int) -> ExportAlignment {
        column < alignments.count ? alignments[column] : .natural
    }
}

nonisolated enum ExportAlignment: Equatable, Sendable {
    case natural
    case leading
    case center
    case trailing
}

/// A span of inline content. Formatting nests, so emphasis inside a link inside
/// a heading survives to every output format.
nonisolated indirect enum ExportInline: Equatable, Sendable {
    case text(String)
    case emphasis([ExportInline])
    case strong([ExportInline])
    case strikethrough([ExportInline])
    case underline([ExportInline])
    case code(String)
    case link(destination: String, content: [ExportInline])
    case image(ExportImage)
    /// A hard line break within a paragraph.
    case lineBreak
}

nonisolated struct ExportImage: Equatable, Sendable {
    /// The source exactly as written in the markdown.
    var source: String
    var alternativeText: String?

    /// An image with empty alt text is decorative by markdown convention, and
    /// every export has to say so explicitly — an untagged image is announced
    /// as "image" with no further information, which is worse than being
    /// skipped outright.
    var isDecorative: Bool { (alternativeText ?? "").isEmpty }
}

// MARK: - Inline text extraction

extension ExportInline {
    /// The plain text of an inline span, ignoring all formatting. Used for
    /// table column measurement, PDF alt text, and anywhere a bare string is
    /// needed.
    var plainText: String {
        switch self {
        case .text(let value):
            return value
        case .emphasis(let children),
             .strong(let children),
             .strikethrough(let children),
             .underline(let children):
            return children.plainText
        case .code(let value):
            return value
        case .link(_, let content):
            return content.plainText
        case .image(let image):
            return image.alternativeText ?? ""
        case .lineBreak:
            return " "
        }
    }
}

extension Array where Element == ExportInline {
    var plainText: String {
        map(\.plainText).joined()
    }

    var isEffectivelyEmpty: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
