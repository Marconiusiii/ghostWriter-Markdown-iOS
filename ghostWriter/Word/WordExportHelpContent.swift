import Foundation

nonisolated enum WordExportHelp {
    static let workflow = [
        "To export the document you are editing, choose File Actions > Share > Word Document, then choose a sharing destination or Save to Files when the file is ready. Word export uses your saved Export settings without an extra options screen.",
        "For a compilation, use a folder’s Export Compilation… action and choose Word Document in Export format. Select and reorder the contents, then choose Export and share…. Compilation Export Help explains inclusion defaults, ordering, heading preservation, and page breaks.",
        "Word compilation uses an opening Heading 1 as each document’s title, even after leading blank paragraphs. If there is no opening Heading 1, it uses the filename. The output name names the exported file without adding another title page.",
        "With Start each document on a new page off, Word inserts an actual empty paragraph between documents when neither boundary already has one. Existing blank paragraphs are preserved. With heading preservation off, only the first title remains Heading 1; Heading 6 stays Heading 6.",
        "Settings > Export > Use smart punctuation optionally converts straight quotes, apostrophes, and three periods in exported prose. It does not change source files. Smart punctuation in exports in Help explains its limitations.",
    ]

    static let theme = [
        "Enable Settings > Export > Use Word Stylesheet, then place a plain-text JSON file named word-theme.json at the root of your active ghostWriter folder in Files. Use the on-device folder or iCloud folder selected in Settings > Files and startup > Document Storage. Every single-document and compilation Word export reads that file again, so edits apply to the next export. If the file is absent or the setting is off, Word uses standard styling. An iCloud file is downloaded when needed; an invalid or unreadable file reports an error. Other export formats are unaffected.",
        "The theme applies across the output, including every document in a compilation. Only supplied settings override the standard styles. The theme does not change Markdown source files, image colors, heading levels, or the page-break and heading-structure toggles. Explicit bold and italic formatting in the source is retained.",
        "Every style sheet must contain version with the number 1. Optional top-level fields are body, headings, quote, code, list, table, and page. Use the exact field names and capitalization. The headings object accepts keys 1 through 6, written in quotes, to style the resulting Word heading levels after any compilation heading changes.",
        "The body, each heading, quote, code, list, and table objects accept font, size, color, bold, italic, spaceBefore, spaceAfter, lineSpacing, and alignment. Font is a name such as Georgia or Arial, with 1 to 128 characters and no control characters. Fonts are not embedded; Word substitutes a font if the named font is unavailable. Size is 1 to 200 points and is rounded to the nearest half point. Color is six hexadecimal digits without #, such as 203864. Bold and italic are true or false, without quotes.",
        "SpaceBefore and spaceAfter set paragraph spacing from 0 to 720 points. Use the JSON spellings spaceBefore and spaceAfter, starting with a lowercase s. LineSpacing is a multiplier from 0.5 to 5, such as 1.5 for one-and-a-half spacing; its JSON spelling is lineSpacing. Alignment is left, center, right, or justify, in quotes. Spacing and alignment in code apply to code-block paragraphs; inline code uses only the font, size, color, bold, and italic settings.",
        "The page object accepts width, height, top, right, bottom, and left, all in points. There are 72 points in an inch. Width and height must each be 144 to 1584 points. Margins must each be 0 to 720 points and must leave at least 72 points of content width and height. Without page settings, Word output uses US Letter, 612 by 792 points, with 72-point margins. Paragraph and page measurements are rounded to the nearest twentieth of a point.",
        "Body settings are inherited by paragraph styles unless a more specific style supplies its own setting. Standard heading sizes, bold headings, and monospaced code remain unless overridden in their respective objects. List settings style list text and paragraphs; numbering, starting numbers, and nesting still follow the source. Table settings style table text and paragraphs; table borders and header-row structure retain the standard output.",
        "Keep the JSON file at or below 64 KiB. Omit settings you do not want to change rather than writing null. Unknown fields, unsupported versions, incorrect value types, and out-of-range values prevent Word export and produce an error. Correct the named setting in word-theme.json and export again, or turn off Use Word Stylesheet for standard styling. JSON requires double quotes around field names and text values; comments and trailing commas are not allowed.",
        "The following complete example can be copied into a plain-text file named word-theme.json. Change or omit optional settings to suit your document."
    ]

    static let example = """
    {
      "version": 1,
      "body": { "font": "Georgia", "size": 12, "color": "202020", "spaceAfter": 8, "lineSpacing": 1.15 },
      "headings": {
        "1": { "font": "Arial", "size": 24, "color": "203864", "bold": true, "spaceBefore": 12, "spaceAfter": 8 },
        "2": { "font": "Arial", "size": 18, "color": "203864", "spaceBefore": 10, "spaceAfter": 6 },
        "3": { "size": 15 },
        "4": { "size": 13 },
        "5": { "size": 12 },
        "6": { "size": 12, "italic": true }
      },
      "quote": { "italic": true, "spaceBefore": 6, "spaceAfter": 6 },
      "code": { "font": "Courier New", "size": 10, "alignment": "left" },
      "list": { "spaceAfter": 4 },
      "table": { "font": "Arial", "size": 11 },
      "page": { "width": 612, "height": 792, "top": 72, "right": 72, "bottom": 72, "left": 72 }
    }
    """
}

