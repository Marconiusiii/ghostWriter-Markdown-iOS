import Foundation

nonisolated enum WordExportHelp {
    static let workflow = [
        "To export your open document, choose File Actions > Share > Word Document. To combine documents, choose Export Compilation… on a folder and select Word Document. When the file is ready, share it or choose Save to Files.",
        "Headings become Word heading styles, lists become Word lists, and tables use their first row as column headings. Links and supported text formatting are retained. Quotes and code blocks receive paragraph styles.",
        "Task items begin with Completed or Not completed rather than interactive checkboxes. Review the result in Word when preparing a document for publication.",
        "Settings > Export > Thematic separator chooses a centered decoration for Markdown thematic breaks such as --- on their own line. None omits the separator. The same choice applies to Plain Text and to compilations.",
        "Word uses standard styling by default. For a custom theme, follow Word Stylesheet. Compilation Export explains document order, page breaks, and heading levels; Smart punctuation in exports explains optional punctuation conversion."
    ]

    static let theme = [
        "To apply your own theme to Word exports, turn on Settings > Export > Use Word Stylesheet. The app creates a Word Stylesheets folder and shows its location and stylesheet status.",
        "In Files, place a plain-text JSON file named word-theme.json inside that Word Stylesheets folder. Use the ghostWriter storage location selected in Settings > Files > Document Storage, either on-device or iCloud. Word Stylesheet reference lists the supported fields and provides an example you can copy.",
        "The theme applies to individual Word exports and every document in a Word compilation. Changes to the file apply to the next export. Only settings you supply override the standard styles; your Markdown source and other export formats are unchanged.",
        "If the setting is off or the file is missing, exports use standard styling. An iCloud stylesheet downloads when needed. If the file is invalid or unreadable, correct the reported problem or turn off Use Word Stylesheet to export with standard styling.",
        "A stylesheet changes appearance, not heading levels or compilation page-break choices. Explicit bold and italic formatting is retained. Fonts are not embedded, so Word may substitute an unavailable font."
    ]

    static let reference = [
        "Every style sheet must contain version with the number 1. Optional top-level fields are body, headings, quote, code, list, table, and page. Use the exact field names and capitalization. The headings object accepts keys 1 through 6, written in quotes, to style the resulting Word heading levels after any compilation heading changes.",
        "The body, each heading, quote, code, list, and table objects accept font, size, color, bold, italic, spaceBefore, spaceAfter, lineSpacing, and alignment. Font is a name such as Georgia or Arial, with 1 to 128 characters and no control characters. Size is 1 to 200 points and is rounded to the nearest half point. Color is six hexadecimal digits without #, such as 203864. Bold and italic are true or false, without quotes.",
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

