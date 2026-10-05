# Word export

To export your open document, choose File Actions > Share > Word Document. To combine documents, choose Export Compilation… on a folder and select Word Document. When the file is ready, share it or choose Save to Files.

Headings become Word heading styles, lists become Word lists, and tables use their first row as column headings. Links and supported text formatting are retained. Quotes and code blocks receive paragraph styles.

Task items begin with Completed or Not completed rather than interactive checkboxes. Review the result in Word when preparing a document for publication.

Settings > Export > Thematic separator chooses a centered decoration for Markdown thematic breaks such as --- on their own line. None omits the separator. The same choice applies to Plain Text and to compilations unless the selected Word stylesheet specifies thematicBreak.

Word uses standard styling by default. For a custom theme, follow Word Stylesheet. Compilation Export explains document order, page breaks, and heading levels; Smart punctuation in exports explains optional punctuation conversion.

## Named stylesheets

Choose a stylesheet with the wheel picker when exporting a Word document or compilation. Standard Word output uses normal formatting. Your selection is remembered for the next Word export.

In Files, add named JSON files to Word Stylesheets in your active ghostWriter storage location. The folder is created when you open Word export options. A Large Print stylesheet is supplied once. Existing word-theme.json files are supported. The folder is reserved for stylesheets and does not appear among writing documents.

The exporter checks the files and explains invalid or unavailable choices. Correct the reported problem or choose Standard Word output. A selected file is read again at export time so changes apply to the next export.

Optional title and subtitle definitions format only an opening Heading 1 immediately followed by Heading 2, allowing blank lines. Both definitions must be present. When the pair qualifies, its Heading 1 supplies the title even if the filename is different. Any intervening content, a missing definition, or a missing heading leaves both headings with standard formatting. Later pairs do not qualify. They remain Word Heading 1 and Heading 2 for structure and heading navigation.

In compilations, only the first source document can supply the opening title and subtitle pair. Preserve individual document heading structure must be on. Generated filename headings do not create a pair.

A stylesheet can override the global thematic separator for Word, add paragraph indentation and pagination, and supply headers, footers, and page numbers. Plain Text continues using the global thematic separator. Fonts are not embedded, so Word may substitute an unavailable font.

## JSON specification

Every style sheet must contain version with the number 1. Existing version 1 files remain supported; older app builds may reject files containing the new optional properties. Optional top-level fields are body, headings, quote, code, list, table, page, title, subtitle, thematicBreak, header, footer, differentFirstPage, paragraphAfterHeading, and metadata. Use the exact field names and capitalization. The headings object accepts keys 1 through 6, written in quotes, to style the resulting Word heading levels after any compilation heading changes.

The body, each heading, quote, code, list, and table objects accept font, size, color, bold, italic, spaceBefore, spaceAfter, lineSpacing, and alignment. Font is a name such as Georgia or Arial, with 1 to 128 characters and no control characters. Size is 1 to 200 points and is rounded to the nearest half point. Color is six hexadecimal digits without #, such as 203864. Bold and italic are true or false, without quotes.

SpaceBefore and spaceAfter set paragraph spacing from 0 to 720 points. Use the JSON spellings spaceBefore and spaceAfter, starting with a lowercase s. LineSpacing is a multiplier from 0.5 to 5, such as 1.5 for one-and-a-half spacing; its JSON spelling is lineSpacing. Alignment is left, center, right, or justify, in quotes. Spacing and alignment in code apply to code-block paragraphs; inline code uses only the font, size, color, bold, and italic settings.

The page object accepts width, height, top, right, bottom, and left, all in points. There are 72 points in an inch. Width and height must each be 144 to 1584 points. Margins must each be 0 to 720 points and must leave at least 72 points of content width and height. Without page settings, Word output uses US Letter, 612 by 792 points, with 72-point margins. Paragraph and page measurements are rounded to the nearest twentieth of a point.

Body settings are inherited by paragraph styles unless a more specific style supplies its own setting. Standard heading sizes, bold headings, and monospaced code remain unless overridden in their respective objects. List settings style list text and paragraphs; numbering, starting numbers, and nesting still follow the source. Table settings style table text and paragraphs; table borders and header-row structure retain the standard output.

Keep the JSON file at or below 64 KiB. Omit settings you do not want to change rather than writing null. Unknown fields, unsupported versions, incorrect value types, and out-of-range values prevent Word export and produce an error. Correct the named setting in word-theme.json and export again, or choose Standard Word output. JSON requires double quotes around field names and text values; comments and trailing commas are not allowed.

### Additional paragraph and document settings

widowControl asks Word to keep at least two paragraph lines together at the top and bottom of a page. keepLinesTogether asks Word to keep a paragraph on one page when it fits. These differ from keepWithNext, which keeps a paragraph with the next paragraph. Set them on body or on a specific paragraph style. Word determines pagination using the fonts and page settings available when the document is opened.

paragraphAfterHeading contains headingLevels, a nonempty array of distinct numbers from 1 to 6, and firstLineIndent, a number from 0 to 720 points. For example, set headingLevels to [1, 2] and firstLineIndent to 0 to remove indentation from the first body paragraph after Heading 1 or Heading 2 while body.firstLineIndent supplies the normal indent. Blank paragraphs are ignored. A new heading replaces the previous heading; a list, table, quote, code block, image, or thematic break ends the rule. It does not apply inside tables or carry between compilation source documents. Heading levels are the resulting Word levels after compilation heading changes.

For placeholders, give header or footer a template instead of text and pageNumber. A template accepts up to 1024 characters on one line, with placeholders {{title}}, {{subtitle}}, {{author}}, {{heading1}}, {{heading2}}, {{pageNumber}}, and {{date}}. Names are case-sensitive. Unknown placeholders and unmatched double braces are errors. Existing text remains literal and never expands placeholders.

metadata accepts optional title, subtitle, and author strings, each at most 1024 characters on one line. The title placeholder uses metadata.title or the export title when omitted. Subtitle and author use the corresponding metadata values, or empty text when omitted. Metadata supplies export information without inserting a title page or changing Markdown. It is separate from the title and subtitle paragraph styles. Missing values leave surrounding template punctuation in place. The date placeholder is the export date in UTC, written as YYYY-MM-DD.

The pageNumber placeholder creates a Word PAGE field. heading1 and heading2 create Word STYLEREF fields that use the exported Heading 1 and Heading 2 styles. In Word print layout, these look for the first matching heading on the page, then preceding pages, then following pages. A heading level absent from the document produces empty text. Word evaluates these fields as it lays out the document; other readers or previews may show cached values. Update fields in Word before final printing or sharing. Optional title and subtitle formatting retains heading structure and therefore still participates in heading fields.

Paragraph styles accept firstLineIndent in points from 0 to 720, plus true or false for pageBreakBefore, pageBreakAfter, keepWithNext, widowControl, and keepLinesTogether. Omit a property to inherit its value. Page break after inserts a page break after the paragraph. The table object does not accept pageBreakBefore or pageBreakAfter; page breaks are not inserted inside table cells. Heading styles can use keepWithNext to stay with the following paragraph.

Optional title and subtitle objects accept the same properties as other paragraph styles. Define both to enable opening-pair formatting. The default example and Large Print stylesheet omit both.

thematicBreak accepts behavior set to separator, omit, or pageBreak. For separator, supply text containing 1 to 128 characters on one line. Omit text for the other behaviors. If thematicBreak is absent, the global thematic separator applies.

header and footer each accept text, pageNumber, and alignment. Text is literal text of at most 1024 characters on one line. pageNumber is true or false and appends an automatic Word page number after the text. Include any wanted space in the text, such as Page followed by a space. Alignment is left, center, or right; the default is left.

Set differentFirstPage to true to leave the first page's header and footer blank. Headers, footers, and page numbering apply to the whole exported document, including compilations. Header and footer distances are 18 points from the page edge; leave sufficient page margins for their text. Use heading placeholders for running chapter headings. Separate section layouts, odd/even headers, and numbering restarts are not supported.

## Default stylesheet example

```json
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
```
