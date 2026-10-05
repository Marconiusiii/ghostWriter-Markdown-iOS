# Testing the Word stylesheet features

Use Stylesheet test document.md with word-manuscript.json. These files are supplied separately from the TestFlight app.

## Set up

1. Import Stylesheet test document.md into the ghostWriter Library.
2. Open the Word export options once to create the Word Stylesheets folder if needed. In Files, add word-manuscript.json to that folder in your active ghostWriter storage location.
3. In the JSON, replace metadata.author's "Your name" with your name.
4. Export the test document as Word and select the manuscript stylesheet. Open the result in Microsoft Word.
5. Keep the original JSON as a reference. Make one change at a time in a copy, select that copy during export, and export again to compare results. Use Word's paragraph settings to inspect indentation and pagination options; you do not have to judge them by appearance alone.

## First paragraphs after headings

The chapter headings are Heading 1. The letter, The blue cupboard, and the other section headings are Heading 2. A decision before breakfast and What to keep are Heading 3.

With the supplied stylesheet, the first body paragraph after Heading 1 or Heading 2 should have no first-line indent. Subsequent body paragraphs should have a 24-point first-line indent. The first paragraph after Heading 3 should also be indented because the rule applies only to levels 1 and 2.

For a comparison, change paragraphAfterHeading.headingLevels to [1]. First paragraphs after Heading 2 should then use the normal body indent, while first paragraphs after Heading 1 remain unindented.

## Paragraphs near page boundaries

The letter and The blue cupboard each contain a longer paragraph for pagination checks.

The supplied body style has widowControl set to true and keepLinesTogether set to false. Word should avoid leaving a single paragraph line at the top or bottom of a page, but may split a longer paragraph across pages. The Heading 1 and Heading 2 styles also keep headings with the paragraph that follows.

For a comparison, set body.keepLinesTogether to true. A paragraph that fits on a whole page should stay together, moving to the next page if necessary. A paragraph longer than a page must still split. Separately, compare body.widowControl set to false and true while keepLinesTogether is false.

Exact page breaks depend on Word's fonts and page layout. If a paragraph does not cross a page boundary, add text before it in a copy of the Markdown document and export again. Check the paragraph settings in Word as well as the resulting page break; an unchanged page break alone does not mean the setting failed.

## Headers and footers

The supplied header shows your author name and a Heading 1 value. The footer shows the document title and page number. The first page has no header or footer because differentFirstPage is true.

Check pages in different chapters in Word's print layout. The heading1 placeholder uses the first Heading 1 on the page, or searches preceding pages and then following pages if that page has none. It does not necessarily mean the last heading read on that page.

For a comparison, change header.template to "{{author}}: {{heading2}}" to use section headings. To test the other metadata placeholders, add title and subtitle strings inside metadata, then try footer.template set to "{{title}} | {{subtitle}} | {{date}} | {{pageNumber}}". The date is the export date in UTC. Metadata changes header/footer text; it does not insert a title page.

Update fields in Word before judging heading and page-number results. The full supported settings are in the app's Help Manual and in Word export.md in the parent Documentation folder.

## Word table of contents

The supplied stylesheet includes heading levels 1 through 3. The contents should follow the opening document title, include all three chapter headings and their sections, and omit the opening title itself.

1. Follow entries to different chapters and sections.
2. Update the entire table in Word to calculate page numbers. Compare those numbers with the destinations.
3. Change tableOfContents.maximumLevel to 2 and export again. A decision before breakfast and What to keep should be omitted from the contents but remain in the document.
4. Set tableOfContents.pageNumbers to false to test contents without page numbers. Set tableOfContents.pageBreakAfter to false to allow the body to follow without a forced page break.

## Optional HTML and PDF checks

These exports use their own Table of Contents toggle, not the Word JSON stylesheet.

For HTML, enable the toggle and open the export in a browser. The title should be followed by a collapsed Table of Contents disclosure. Expand it and activate chapter and section links.

For PDF, enable the toggle and open the export in Preview or Acrobat Reader. With VoiceOver, activate entries to different pages and confirm you can read the destination heading and following text. Compare the printed contents page numbers with the destinations.

## Send feedback

Please include the JSON you used, the Markdown document or a short example, your Word version, and what you expected compared with what happened. Your own manuscript is also useful for testing realistic page breaks and chapter layouts.
