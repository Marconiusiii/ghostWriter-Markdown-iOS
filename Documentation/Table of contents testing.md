# Testing table of contents exports

Import The night library.md into the Library. For Word, add word-manuscript.json to the Word Stylesheets folder and select it during export.

## HTML

1. Export the document as HTML and turn on Table of Contents.
2. Confirm the document title comes first, followed by a collapsed Table of Contents disclosure. Activate its summary to expand the nested list of links, then activate it again to collapse the list. Check this with both keyboard navigation and VoiceOver.
3. Follow entries in several chapters, including the repeated Notes from the reading room headings. Each link should reach its own heading.
4. Confirm A deeper shelf nests under its parent and the heading inside the code block is absent.
5. Export again with the toggle off and confirm no contents is added.

## PDF

1. Export as PDF with Table of Contents on.
2. Open the PDF in macOS Preview. With VoiceOver, activate contents links to early, middle, and later pages. Confirm each activation reaches the destination page and that you can read its heading and following text. Repeat in Acrobat Reader. Recognizing an entry as a link is not sufficient; activation must work.
3. Check the printed page references against the destination pages, including the last chapter. The document body begins on a new page after the contents.
4. Repeat with a compilation containing this document twice. Confirm links to repeated headings reach the correct source document.

## Word

1. Export with the manuscript stylesheet selected.
2. Confirm the linked entries are present immediately, the opening title is absent from the contents, and A deeper shelf is omitted by the example's maximumLevel of 3.
3. In Word, update the entire table to calculate page numbers. Follow several links and compare their page references with the destination pages.
4. Edit the body enough to change pagination, update the entire table again, and check that the contents does not list itself or add the opening title.
5. In a copy of the JSON, set pageNumbers and pageBreakAfter to false. Export and confirm these options are honored.
6. Repeat with a compilation and both choices for Preserve individual document heading structure. Contents entries should follow the resulting heading levels and document order.

The JSON example's author value is a placeholder. Replace it with the author's name before using it for publication. The test document has no Word title/subtitle style pair; its Heading 2 chapters remain ordinary headings.
