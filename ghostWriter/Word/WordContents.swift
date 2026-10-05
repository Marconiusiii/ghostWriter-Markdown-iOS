import Foundation

/// A native TOC field with a populated, linked cache. Its bookmark range omits
/// the opening title/subtitle without changing their accessible heading styles.
nonisolated struct WordContents {
    var insertionIndex = 0
    var entries: [(level: Int, text: String, bookmark: String)] = []
    let options: WordThemeContents

    init(document: WordDocumentModel, options: WordThemeContents, recognizesSubtitle: Bool = false) {
        self.options = options
        let first = document.blocks.firstIndex { block in
            if case .paragraph(let p) = block {
                return p.headingLevel != nil || p.runs.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.image != nil }
            }
            return true
        }
        if let first, case .paragraph(let p) = document.blocks[first], p.headingLevel == 1 {
            insertionIndex = first + 1
            if recognizesSubtitle, p.openingStyle == "title" {
                var next = insertionIndex
                while next < document.blocks.count, case .paragraph(let paragraph) = document.blocks[next] {
                    if paragraph.openingStyle == "subtitle" { insertionIndex = next + 1; break }
                    if paragraph.headingLevel != nil || paragraph.runs.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { break }
                    next += 1
                }
            }
        }
        var number = 0
        func collect(_ blocks: [WordBlock], included: Bool) {
            for block in blocks {
                switch block {
                case .paragraph(let p):
                    guard let level = p.headingLevel else { continue }
                    number += 1
                    let text = p.runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    if included, !text.isEmpty, ((options.minimumLevel ?? 1)...(options.maximumLevel ?? 3)).contains(level) {
                        entries.append((level, text, "GWHeading\(number)"))
                    }
                case .table(let table):
                    for row in table.rows { for cell in row.cells { collect(cell, included: included) } }
                }
            }
        }
        collect(Array(document.blocks.prefix(insertionIndex)), included: false)
        collect(Array(document.blocks.dropFirst(insertionIndex)), included: true)
    }

    var xml: String {
        guard !entries.isEmpty else { return "" }
        let pages = options.pageNumbers ?? true
        let instruction = " TOC \\o \"\(options.minimumLevel ?? 1)-\(options.maximumLevel ?? 3)\" \\h \\b GWContentsBody" + (pages ? " " : " \\n ")
        var result = "<w:p><w:pPr><w:pStyle w:val=\"TOCHeading\"/></w:pPr><w:r><w:t>\(MarkdownRenderer.escape(options.title ?? "Table of Contents"))</w:t></w:r></w:p>"
        result += "<w:p><w:r><w:fldChar w:fldCharType=\"begin\" w:dirty=\"true\"/></w:r><w:r><w:instrText xml:space=\"preserve\">\(MarkdownRenderer.escape(instruction))</w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r></w:p>"
        for entry in entries {
            result += "<w:p><w:pPr><w:pStyle w:val=\"TOC\(entry.level)\"/></w:pPr><w:hyperlink w:anchor=\"\(entry.bookmark)\"><w:r><w:t>\(MarkdownRenderer.escape(entry.text))</w:t></w:r></w:hyperlink>"
            if pages {
                result += "<w:r><w:tab/></w:r><w:fldSimple w:instr=\" PAGEREF \(entry.bookmark) \\h \" w:dirty=\"true\"><w:r><w:t></w:t></w:r></w:fldSimple>"
            }
            result += "</w:p>"
        }
        result += "<w:p><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>"
        if options.pageBreakAfter ?? true { result += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }
        return result
    }
}
