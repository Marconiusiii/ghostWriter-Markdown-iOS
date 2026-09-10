import Foundation

nonisolated enum WordExportHelp {
    static let workflow = [
        "To export the document you are editing, choose File Actions > Share > Word Document. Optionally import a JSON style sheet, then activate Export and share… and choose a sharing destination or Save to Files.",
        "To combine documents, use a folder’s Export Compilation… action in its long-press context menu or VoiceOver Actions. You can do this from the parent folder without opening the selected folder. The Exporter starts with all documents in that folder, including nested folders. Choose Add documents or folders… to include other Library items.",
        "Documents in export order lists the files that will be combined. Folders expand where they occur in the saved Manual order. Within each folder, items without saved positions follow the saved items alphabetically. Pinning and the current Library sort do not change compilation order.",
        "Choose Add documents or folders… to include more files. Turn on Include document or Include folder for each item you want, then choose Add. Include folder adds all documents in that folder and its nested folders. Open folder lets you choose individual contents instead; Go to parent folder moves up one level. Selecting a folder and one of its documents includes that document only once. New selections append to the compilation in saved Library order.",
        "Choose Edit to reorder or remove documents, then Done. The system’s reorder controls move documents within the compilation. Remove from compilation also appears in a document’s context menu. Removing or rearranging a document here does not change its Library file or saved Library order.",
        "Enter the output name in Document name. Each source document begins with its own title. If its first paragraph is already a matching Heading 1, that heading supplies the title. The output name names the exported file; it does not insert an additional title page.",
        "Start each document on a new page is on by default. It begins every document after the first on a new page. Turn it off to let documents flow consecutively. Paragraphs, lists, tables, and images retain their boundaries. A long document can still occupy several pages.",
        "Preserve individual document heading structure is on by default and retains the heading levels in each document. Turn it off to keep only the first document’s title as Heading 1. Every other heading, including other headings in the first document, moves down one level: Heading 1 becomes Heading 2, Heading 2 becomes Heading 3, and so on. This follows document order, whether page breaks are on or off.",
        "Heading 6 remains Heading 6; it never becomes Heading 7. Heading 5 and Heading 6 can therefore both become Heading 6, losing the distinction between those two levels. The Exporter displays this warning when heading preservation is off.",
        "Activate Export and share… to create the Word file. Documents stored only in iCloud are downloaded first. If a document cannot be read, the Exporter identifies the problem so you can retry; it does not share a compilation with that document silently omitted."
    ]

    static let theme = [
        "A JSON style sheet is an optional plain-text .json file that describes the appearance of the exported Word document. Choose Import JSON style sheet… and select the file in Files. The selected file name appears in the Exporter. Choose Remove style sheet to return to the standard Word appearance. The theme applies to this export and is not saved as a future default.",
        "The theme applies across the output, including every document in a compilation. Only supplied settings override the standard styles. The theme does not change Markdown source files, image colors, heading levels, or the page-break and heading-structure toggles. Explicit bold and italic formatting in the source is retained.",
        "Every style sheet must contain version with the number 1. Optional top-level fields are body, headings, quote, code, list, table, and page. Use the exact field names and capitalization. The headings object accepts keys 1 through 6, written in quotes, to style the resulting Word heading levels after any compilation heading changes.",
        "The body, each heading, quote, code, list, and table objects accept font, size, color, bold, italic, spaceBefore, spaceAfter, lineSpacing, and alignment. Font is a name such as Georgia or Arial, with 1 to 128 characters and no control characters. Fonts are not embedded; Word substitutes a font if the named font is unavailable. Size is 1 to 200 points and is rounded to the nearest half point. Color is six hexadecimal digits without #, such as 203864. Bold and italic are true or false, without quotes.",
        "SpaceBefore and spaceAfter set paragraph spacing from 0 to 720 points. Use the JSON spellings spaceBefore and spaceAfter, starting with a lowercase s. LineSpacing is a multiplier from 0.5 to 5, such as 1.5 for one-and-a-half spacing; its JSON spelling is lineSpacing. Alignment is left, center, right, or justify, in quotes. Spacing and alignment in code apply to code-block paragraphs; inline code uses only the font, size, color, bold, and italic settings.",
        "The page object accepts width, height, top, right, bottom, and left, all in points. There are 72 points in an inch. Width and height must each be 144 to 1584 points. Margins must each be 0 to 720 points and must leave at least 72 points of content width and height. Without page settings, Word output uses US Letter, 612 by 792 points, with 72-point margins. Paragraph and page measurements are rounded to the nearest twentieth of a point.",
        "Body settings are inherited by paragraph styles unless a more specific style supplies its own setting. Standard heading sizes, bold headings, and monospaced code remain unless overridden in their respective objects. List settings style list text and paragraphs; numbering, starting numbers, and nesting still follow the source. Table settings style table text and paragraphs; table borders and header-row structure retain the standard output.",
        "Keep the JSON file at or below 64 KiB. Omit settings you do not want to change rather than writing null. Unknown fields, unsupported versions, incorrect value types, and out-of-range values prevent import and produce an error. The previous valid theme remains selected if another import fails. Correct the named setting and import the file again. JSON requires double quotes around field names and text values; comments and trailing commas are not allowed.",
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

