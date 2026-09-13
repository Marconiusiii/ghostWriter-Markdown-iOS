# ghostWriter Help Manual

Open ghostWriter Help Manual in the library or from the button at the top of Help. The manual is editable immediately, but changes are not saved automatically. When you go Back with changes, choose Save to keep them, Don’t Save to discard them and return to the Library, or Cancel to continue editing. File Actions > Save Now explicitly saves your changes. Previously saved changes remain when you reopen the manual.

## Markdown and writing

### Getting started with Markdown

Markdown lets you write a formatted document using plain text. You type simple punctuation marks for headings, lists, and emphasis, then use Render to read the formatted result.

Press Return twice to start a new paragraph. This leaves one empty line between paragraphs. Lines without an empty line separating them will get parsed as a single paragraph when rendered or exported.

Begin a heading with a number sign and a space, such as # My title. Use ## for a subsection and ### for a section within it. Heading levels run from 1 to 6 and give your document a structure readers can navigate.

Put **two asterisks** around bold text or *one asterisk* around italic text. Begin a bulleted item with a hyphen and a space, or a numbered item with 1. and a space. The Insert feature can add formatting for you when working in the Editor.

Open File Actions > Markdown Reference in the editor for explanations and examples you can copy, including links, images, tables, and code.

### Creating and opening documents

Choose New in the Library to create a document. Depending on When Starting a New Document in Settings, you will be asked for a name or the document will use today’s date. Choose a document in the Library to open it.

Choose New Folder to create a folder in your current location. Open a folder to work inside it, and use Back to return to its parent.

Import copies Markdown, plain-text, Word, or PowerPoint files from Files into your current folder. Word and PowerPoint documents are converted to Markdown. If a name is already in use, the copy receives a numbered name. See the format-specific topics for conversion options and limitations.

### Writing and editing

Write and revise your Markdown in the editor. File Actions provides saving, sharing, Find and Replace, Jump to Line, and the Markdown Reference.

Use Insert to add formatting at the cursor or apply supported formatting to selected text. For a link, selected text becomes the suggested link text. Enter a destination such as https://example.com or mailto:name@example.com.

Headings organize sections; lists organize related items or steps. Use a block quote for quoted material, inline code for short literal text, and a code block for several preformatted lines. A horizontal rule marks a thematic break.

Table asks for the number of columns and rows. The first row contains column headings and counts toward the number of rows. Give each row a clear first entry if it needs a label.

Choose Jump to Line in File Actions, enter a line number starting at 1, and choose Jump to place the cursor at that line.

### Lists and indentation

When Automatic Lists is enabled, pressing Return after a bullet, numbered item, or task continues that list. Press Return on an empty list item to end the list.

Use Indent and Outdent above the on-screen keyboard to change the nesting level of the current line or selected lines. Choose tabs, two spaces, or four spaces in Settings > Editing.

### Outline and formatted preview

Outline lists your headings in document order and identifies their levels. Choose a heading to move to that part of the document.

Render opens a formatted HTML preview. Use it to read your work with its headings, paragraphs, lists, and other formatting applied. Choose Done to return to the editor.

### Images and descriptions

Choose Insert, then Image from Files or Image from Photo Library to attach a picture. Enter alternative text describing what the image communicates, or mark it decorative if it adds no information. The image is stored with the document and referenced in its Markdown.

Image from Web inserts a link to an image at an http:// or https:// address. Rendering may contact that website to load the image, and the image remains dependent on its availability.

Choose Tactile Graphic for an SVG, PNG, or JPG prepared for tactile presentation. Supply a description so readers can understand its purpose.

## Library and storage

### Saving and storage

ghostWriter saves automatically after you pause typing and when the app moves into the background. Choose Save Now in File Actions to request an immediate save.

Your documents are ordinary Markdown files in the ghostWriter folder, which you can also open in Files. Settings > Files > Document Storage chooses on-device or iCloud storage. Follow the prompts when changing locations.

Files can be accessed through whatever storage apps you have available through the iOS Files app, so OneDrive, Google Drive, Dropbox, and more can be used. Files imported from there will be copied into the currently selected ghostWriter storage location, either iCloud or on-device.

### Finding and organizing documents

Search in the Library checks document names and contents.

Use Sort to choose Sort By and Sort Order. The Library and each folder remember their own sorting choices. Last Opened sorts by when documents were most recently opened in the editor.

Choose Manual sorting to arrange items yourself. With Search cleared and at least two items available, choose Edit, move items with the reorder controls, then choose Done Editing. Folders and unpinned documents can be arranged together.

Pin keeps documents at the beginning of the document group. In Manual order, pinned documents can be reordered within their own group. Pinning does not affect compilation exports.

Touch and hold a file or folder to open its actions, or use its VoiceOver Actions. These include renaming, moving, and deleting; files also offer actions such as duplication and sharing.

Delete moves an item to Deleted. Restore returns it to its previous folder if that folder still exists, or to Documents otherwise. Deleting and restoring a folder keeps its contents together. Permanent deletion cannot be undone.

### Folder statistics

Use Total Word Count to check the length of a folder’s Markdown documents, including nested folders. Totals include words, sentences, characters, and the number of documents counted. Saved compilation exclusions also exclude files and folders from all these totals. Find it in the folder’s context menu or accessibility actions, or in its heading actions when the folder is open.

The result reports words, sentences, characters, and documents counted out of all Markdown documents in the folder and nested folders. Words use the same count as the editor; characters include Markdown marks, spaces, and line breaks. Sentences use automatic language analysis of the source; headings and list fragments can count as sentences.

Progress appears while documents are read or downloaded. If a file cannot be read, the result is marked Partial total and identifies the omitted files. Cancel stops the count.

### Touch gestures

Without VoiceOver, swipe on Library items to reveal common actions. Swipe left on a document for Share and Delete, or right for Pin or Unpin. A failed download also offers Retry Download.

For folders, swipe left for Move and Delete, or right for Rename. Touch and hold either kind of item for its full actions menu.

## Accessibility and Settings

### VoiceOver

Settings > VoiceOver Settings contains Verbosity and Heading Swipe Navigation. VoiceOver Verbosity controls Markdown editing announcements. Off makes no Markdown editing announcements. Light announces list changes, indentation levels, and Insert actions. Full also announces completed Markdown structures as you type.

Heading Swipe Navigation moves between headings in the editor. Swipe right with three fingers for the next heading, or left with three fingers for the previous heading. These gestures are not available while using Braille Screen Input or when assigned to other VoiceOver commands.

Use VoiceOver Actions on Library files and folders to reach their available commands. An open folder’s heading also offers folder actions.

### Keyboard shortcuts

Enable Keyboard Shortcuts under Editing in Settings to use the app’s hardware keyboard commands.

In the Library, Command-N creates a document, Command-O imports files, and Command-comma opens Settings.

In the editor, use Command-S for Save Now, Command-F for Find and Replace, Command-R for Render, Command-Shift-O for Outline, Command-Shift-I for Insert, Command-J for Jump to Line, and Command-W to close the editor.

Press Escape to dismiss the editor keyboard.

### Settings

When App Opens chooses whether to begin in the Library, a new document, or your last document. When Starting a New Document chooses whether to ask for a name or use today’s date.

Editing contains Indentation, Automatic Lists, and Keyboard Shortcuts. VoiceOver Settings controls editing feedback and heading navigation; see VoiceOver for details.

Appearance contains Theme and Editor Font. Status Bar displays document information below the editor; Customize Status Bar chooses what it shows. Render Sound plays when rendering and follows the device’s silent switch.

Export contains Use smart punctuation and Thematic separator. Choose a Word stylesheet in the Word export flow. Their Help topics explain what they change. Set eBraille Defaults under eBraille metadata supplies information for new exports.

## Sharing and compilations

### Sharing a document

In the editor, choose File Actions > Share, then an export format. When the output is ready, choose an app or Save to Files from the Share Sheet. Library file actions also offer sharing.

Choose Markdown to continue editing the source, Plain Text for text without Markdown marks, HTML for a web document, Word Document for a Word file, or PDF for fixed pages. EPUB is a reflowable ebook, PowerPoint is a presentation, and eBraille and Braille Ready Format provide braille output.

To combine several documents into one output, use Export Compilation… on their folder. The following topics explain compilation choices and the details of each format.

### Compilation Export

To combine a folder’s documents, choose Export Compilation… from its context menu or VoiceOver Actions. Inside an open folder, use its heading actions. Enter Document name and choose Export format.

Use the switches in Files and folders to select what to include. Expand a folder to choose individual items inside it. Turning off a folder excludes all of its contents; turning it back on restores the individual selections.

The initial order comes from saved Manual order, regardless of the Library’s current sort or pinned documents. Choose Edit to rearrange files and folders, then Done Editing to return to selection. Moving a folder moves its contents together. These changes apply only to this export.

To save an inclusion preference for future exports, use Exclude from Compilations or Include in Compilations in a file or folder’s Library actions, an open folder’s heading actions, or the editor’s File Actions. These saved exclusions also apply to folder word, sentence, and character totals. Exporting a folder directly always uses that folder as the scope, even if it is excluded from compilations of its parent.

Each document uses its opening Heading 1 as its title, or its filename if it has no opening Heading 1. Document name names the output file; it does not create a title page.

Word and PDF offer Start each document on a new page. Turn it off to let the documents flow together. In Word, an empty paragraph separates documents, as if you pressed Return twice between them.

Preserve individual document heading structure keeps each document’s heading levels. Turn it off to keep only the first document’s title at Heading 1 and move the remaining headings down one level. Heading 6 stays at Heading 6, so original Heading 5 and Heading 6 headings can end up at the same level. This option is available for Word, PDF, HTML, Markdown, EPUB, and eBraille.

Choose the options for your format, then Export and share…. Preparation progress identifies the current document and how many documents have been prepared, including any needed iCloud downloads. The app then creates the output and opens the Share Sheet. Cancel stops the export. If a document or linked file cannot be read, the app reports an error.

If the output arrives as a ZIP, extract it before opening the document and keep the extracted files together so linked images and attachments remain available. Format-specific topics explain Word styles, presentation structure, ebook output, and braille settings.

### Smart punctuation in exports

Turn on Settings > Export > Use smart punctuation to convert straight quotes and apostrophes to curly marks and three periods to an ellipsis (…). It applies to individual and compilation exports in every format. Your saved documents and punctuation in the editor are unchanged.

Code, link destinations, and image paths are left unchanged. Existing curly punctuation and ellipses are kept. Dashes and runs of four or more periods are not converted. For braille output, punctuation is converted before translation.

Review the result before publication. The conversion uses surrounding text to interpret punctuation and can mistake unusual quotations, leading apostrophes, abbreviations, or measurement marks. It does not apply language-specific quotation styles or spacing, or correct existing curly punctuation.

For Markdown export, enabling this option can also change the spelling and spacing of Markdown syntax. Leave it off when you need an unchanged copy of a single document’s Markdown.

### Text, PDF, and ebook formats

Markdown retains editable Markdown syntax. A compilation combines the sources into normalized Markdown, which can change syntax and spacing. If assets are included in a ZIP, extract it and keep the files together.

Plain Text removes Markdown syntax while retaining readable structure. Level 1 and 2 headings are underlined, deeper headings state their level, lists keep bullets and numbers, and tables become aligned columns.

Settings > Export > Thematic separator replaces Markdown thematic breaks with your chosen decoration in Plain Text and Word exports. None omits them. Plain Text centers the characters with spaces within 72 columns; their appearance depends on the font and app used to read the file.

HTML preserves document structure, embeds supported attached images, and retains image descriptions. Its text size follows the app used to open it.

PDF produces tagged, fixed pages with headings, lists, tables, and image descriptions. Pages use US Letter with one-inch margins. Headings stay with the following text, and table rows stay together.

EPUB produces a reflowable ebook with heading navigation and active links. For braille publications, see Braille exports.

## Word and Powerpoint

### Importing Word documents

Choose Import in the Library and select a .docx file. ghostWriter converts it into a Markdown copy. Review the converted document before continuing: Markdown preserves structure but cannot reproduce every Word feature.

Importing a Word document brings across headings, paragraphs, bulleted and numbered lists including nested levels and custom starting numbers, tables, block quotes, code blocks, and links. Bold, italic, underline, strikethrough, and inline code are preserved. Underline becomes a <u> tag, because markdown has no underline syntax of its own.

Images in an imported Word document are saved alongside the markdown file and referenced by name. Alternative text is carried across, and images marked decorative in Word import with empty alternative text. An image without alternative text is reported after import so you can add a description.

Footnotes are imported as markdown footnote references with their text collected at the end of the document. Tracked insertions are imported as ordinary text, and tracked deletions are discarded. Comments are not imported.

Fonts, colors, text size, alignment, columns, headers and footers, page breaks, merged table cells, and embedded objects such as charts are not retained.

### Word Export

To export your open document, choose File Actions > Share > Word Document. To combine documents, choose Export Compilation… on a folder and select Word Document. When the file is ready, share it or choose Save to Files.

Headings become Word heading styles, lists become Word lists, and tables use their first row as column headings. Links and supported text formatting are retained. Quotes and code blocks receive paragraph styles.

Task items begin with Completed or Not completed rather than interactive checkboxes. Review the result in Word when preparing a document for publication.

Settings > Export > Thematic separator chooses a centered decoration for Markdown thematic breaks such as --- on their own line. None omits the separator. The same choice applies to Plain Text and to compilations unless the selected Word stylesheet specifies thematicBreak.

Word uses standard styling by default. For a custom theme, follow Word Stylesheet. Compilation Export explains document order, page breaks, and heading levels; Smart punctuation in exports explains optional punctuation conversion.

### Word Stylesheet

Choose a stylesheet with the wheel picker when exporting a Word document or compilation. Standard Word output uses normal formatting. Your selection is remembered for the next Word export.

In Files, add named JSON files to Word Stylesheets in your active ghostWriter storage location. The folder is created when you open Word export options. A Large Print stylesheet is supplied once. Existing word-theme.json files are supported. The folder is reserved for stylesheets and does not appear among writing documents.

The exporter checks the files and explains invalid or unavailable choices. Correct the reported problem or choose Standard Word output. A selected file is read again at export time so changes apply to the next export.

Optional title and subtitle definitions format only an opening Heading 1 immediately followed by Heading 2, allowing blank lines. Both definitions must be present. When the pair qualifies, its Heading 1 supplies the title even if the filename is different. Any intervening content, a missing definition, or a missing heading leaves both headings with standard formatting. Later pairs do not qualify. They remain Word Heading 1 and Heading 2 for structure and heading navigation.

In compilations, only the first source document can supply the opening title and subtitle pair. Preserve individual document heading structure must be on. Generated filename headings do not create a pair.

A stylesheet can override the global thematic separator for Word, add paragraph indentation and pagination, and supply headers, footers, and page numbers. Plain Text continues using the global thematic separator. Fonts are not embedded, so Word may substitute an unavailable font.

#### Word Stylesheet reference

Every style sheet must contain version with the number 1. Existing version 1 files remain supported; older app builds may reject files containing the new optional properties. Optional top-level fields are body, headings, quote, code, list, table, page, title, subtitle, thematicBreak, header, footer, and differentFirstPage. Use the exact field names and capitalization. The headings object accepts keys 1 through 6, written in quotes, to style the resulting Word heading levels after any compilation heading changes.

The body, each heading, quote, code, list, and table objects accept font, size, color, bold, italic, spaceBefore, spaceAfter, lineSpacing, and alignment. Font is a name such as Georgia or Arial, with 1 to 128 characters and no control characters. Size is 1 to 200 points and is rounded to the nearest half point. Color is six hexadecimal digits without #, such as 203864. Bold and italic are true or false, without quotes.

SpaceBefore and spaceAfter set paragraph spacing from 0 to 720 points. Use the JSON spellings spaceBefore and spaceAfter, starting with a lowercase s. LineSpacing is a multiplier from 0.5 to 5, such as 1.5 for one-and-a-half spacing; its JSON spelling is lineSpacing. Alignment is left, center, right, or justify, in quotes. Spacing and alignment in code apply to code-block paragraphs; inline code uses only the font, size, color, bold, and italic settings.

The page object accepts width, height, top, right, bottom, and left, all in points. There are 72 points in an inch. Width and height must each be 144 to 1584 points. Margins must each be 0 to 720 points and must leave at least 72 points of content width and height. Without page settings, Word output uses US Letter, 612 by 792 points, with 72-point margins. Paragraph and page measurements are rounded to the nearest twentieth of a point.

Body settings are inherited by paragraph styles unless a more specific style supplies its own setting. Standard heading sizes, bold headings, and monospaced code remain unless overridden in their respective objects. List settings style list text and paragraphs; numbering, starting numbers, and nesting still follow the source. Table settings style table text and paragraphs; table borders and header-row structure retain the standard output.

Keep the JSON file at or below 64 KiB. Omit settings you do not want to change rather than writing null. Unknown fields, unsupported versions, incorrect value types, and out-of-range values prevent Word export and produce an error. Correct the named setting in word-theme.json and export again, or choose Standard Word output. JSON requires double quotes around field names and text values; comments and trailing commas are not allowed.

Paragraph styles accept firstLineIndent in points from 0 to 720, plus true or false for pageBreakBefore, pageBreakAfter, and keepWithNext. Omit a property to inherit its value. Page break after inserts a page break after the paragraph. The table object does not accept pageBreakBefore or pageBreakAfter; page breaks are not inserted inside table cells. Heading styles can use keepWithNext to stay with the following paragraph.

Optional title and subtitle objects accept the same properties as other paragraph styles. Define both to enable opening-pair formatting. The default example and Large Print stylesheet omit both.

thematicBreak accepts behavior set to separator, omit, or pageBreak. For separator, supply text containing 1 to 128 characters on one line. Omit text for the other behaviors. If thematicBreak is absent, the global thematic separator applies.

header and footer each accept text, pageNumber, and alignment. Text is literal text of at most 1024 characters on one line. pageNumber is true or false and appends an automatic Word page number after the text. Include any wanted space in the text, such as Page followed by a space. Alignment is left, center, or right; the default is left.

Set differentFirstPage to true to leave the first page's header and footer blank. Headers, footers, and page numbering apply to the whole exported document, including compilations. Header and footer distances are 18 points from the page edge; leave sufficient page margins for their text. Chapter-specific headers, odd/even layouts, and numbering restarts are not supported.

Default stylesheet example:

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

### PowerPoint import

Choose Import and select one or more .pptx presentations from Files. Choose the content to include, then activate Import as Markdown. Each presentation becomes a separate document in the current folder. The original files are unchanged.

Slide text, tables, images, speaker notes, text formatting, and links are included by default. Hidden slides are excluded. Additional options include decorative images, slide numbers, dates, and headers and footers. Your choices are remembered and apply to every presentation in the selected batch.

Turning off Slide text omits body paragraphs and lists but keeps slide headings. Turning off Text formatting keeps the words without emphasis. Turning off Links keeps the link text without its destination. Turning off Images omits pictures and their references. For notes-only import, turn off Slide text, Tables, and Images while leaving Speaker notes on.

Slide titles become level 2 headings. A first slide identified as a title slide becomes a level 1 heading instead. Untitled slides use Slide followed by their original slide number. Repeated titles remain separate sections. Speaker notes follow three asterisks on a line by themselves.

Bulleted and numbered lists retain their structure and nesting. Ordinary tables become markdown tables; tables with merged cells become labeled text rows. Text formatting includes bold, italic, underline, and strikethrough. Supported web and email links remain active. Internal slide links become plain text.

Embedded PNG, JPEG, and safe SVG pictures are saved with the markdown document using relative references. Existing alternative text is retained. Missing descriptions are reported after import. Unsupported or unavailable images keep their descriptions when available. Linked external images are not downloaded.

Slides follow presentation order. Objects follow their stored order, with grouped objects kept together. Visually arranged columns may need editing afterward. Fonts, colors, exact layout, animations, and transitions are not retained. Charts, SmartArt, equations, audio, video, and embedded objects are not converted into editable equivalents. Available descriptions are retained for unsupported objects.

Presentations up to 512 MiB per file are supported. Turn off Images before activating Import as Markdown to skip loading and extracting pictures. The original presentation is unchanged. Images have a separate size allowance from slide text and notes; pictures that exceed image limits are omitted with a notice.

Legacy .ppt files and password-protected presentations are not supported. Other limits include 500 slides and 4,096 internal files and folders. When a size or complexity limit is reached, the message identifies that limit. Invalid presentations do not create a markdown document; other valid files in the batch can still import.

### PowerPoint export

PowerPoint creates a widescreen .pptx presentation. A level 1 heading before the first slide titles the presentation. Content before the first level 2 heading appears on the title slide. Each level 2 heading begins and titles a new slide. Deeper headings and paragraphs become slide text. Put three asterisks on a line by themselves to begin speaker notes, which continue until the next level 2 heading.

PowerPoint keeps bulleted and numbered lists, including nested levels. Task lists become list items beginning with Completed or Not completed, not interactive checkboxes. Links remain clickable, including links inside table cells. Quotes become paragraphs introduced by Quote, and code blocks become monospaced text without syntax highlighting.

PowerPoint tables become editable tables with a header row. Column alignment, supported text formatting, and links are retained. Tables use the selected theme, and text wraps inside cells. Tables and surrounding text stay in Markdown order. Images referenced inside cells appear as separate slide pictures. Tables in speaker notes remain labeled text rows.

PowerPoint includes attached images from Files or the Photo Library and PNG, JPEG, or SVG images linked with HTTPS addresses. Images retain their alternative text. SVG images become high-resolution PNG pictures, preserving their colors and transparency. Unavailable, invalid, or oversized images are skipped while the rest of the presentation exports.

PowerPoint allows up to four included images per slide. If a slide contains too much text, too many images, or a table that is too wide or tall, divide the content with another level 2 heading. Tables keep readable text sizes. The exporter does not automatically split crowded slides.

Choose Presentation theme and Font family to set the presentation’s appearance. These choices are remembered for future exports. Themes affect slide backgrounds, text, and links; image colors are unchanged.

## Braille exports

### Braille exports

Choose eBraille for a reflowable braille publication with heading navigation and active links, or Braille Ready Format for fixed-layout braille. The output filenames end in .ebrl and .brf respectively.

For eBraille, select grade 1 or grade 2 and enter the author, producer, copyright date, and whether the export contains the complete document. Enter the date as a year, year and month, or full date, such as 2026, 2026-04, or 2026-04-17.

Additional eBraille details include source work, publisher, rights, subject, description, and education level.

Braille Ready Format creates fixed-layout Unified English Braille with a .brf filename. Choose Braille display or Emboss on paper. Common page uses 40 cells by 25 lines. Select Custom braille page to choose another number of cells and lines. Lists use braille bullets, tables become labeled rows, tasks state Completed or Not completed, and images become labeled descriptions.

For embossed pages, Include braille page numbers places each number at the bottom right and reserves the final line. Turn it off to use every selected line for document content. Set paper size, physical margins, binding margins, and single-sided or interpoint output in the embossing software.

Braille Ready Format writes a link label followed by its address in parentheses. A link whose label is already the address appears once. Internal document links include the link text without the fragment address. eBraille and EPUB retain active links.

Grade 1 is uncontracted Unified English Braille. Grade 2 is contracted Unified English Braille. Code blocks keep their line breaks and spacing and use uncontracted braille.

The app remembers your braille grade, producer name, and last Braille Ready Format layout. A compilation uses one selected braille code for the entire output, including documents whose source languages differ. Page numbering continues across the combined BRF output.
