//
//  HelpView.swift
//  ghostWriter
//
//  A plain-language guide to the app itself. Markdown syntax has its own
//  reference in the editor; this sheet explains the surrounding workflow.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(HelpTopic.all) { topic in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(topic.paragraphs, id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.body)
                                    .foregroundStyle(Color.ghostText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text(topic.title)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }
}

private struct HelpTopic: Identifiable {
    let title: String
    let paragraphs: [String]

    var id: String { title }

    static let all: [HelpTopic] = [
        HelpTopic(
            title: "Creating and Opening Documents",
            paragraphs: [
                "New creates a named markdown file and opens it for editing.",
                "New Folder creates a folder in your current location. Open a folder to see what is inside, and use Back to return to its parent folder.",
                "Import copies one or more markdown, plain-text, or Word documents from Files into your current folder. Word documents are converted to markdown. Name conflicts receive a safe numbered name.",
                "Choose any document in the library to open it. Folders always appear before documents."
            ]
        ),
        HelpTopic(
            title: "The Markdown Editor",
            paragraphs: [
                "The Markdown Editor is where you write and revise the document’s plain-text markdown.",
                "Markdown punctuation is kept exactly as typed. Smart quotes and smart dashes are disabled so they cannot silently change links, code, or other syntax.",
                "Markdown Reference in File Actions provides examples of supported syntax."
            ]
        ),
        HelpTopic(
            title: "Saving and the Files App",
            paragraphs: [
                "ghostWriter saves changes automatically after you pause typing and when the app moves into the background. Save Now requests an immediate save.",
                "Documents are ordinary markdown files in the ghostWriter folder, available through the Files app."
            ]
        ),
        HelpTopic(
            title: "Automatic Lists and Indentation",
            paragraphs: [
                "When Automatic Lists is enabled, pressing Return after a bullet, numbered item, or task continues that list. Press Return on an empty list item to end the list.",
                "Use Indent and Outdent above the on-screen keyboard to change the nesting level of the current line or selected lines. Choose tabs, two spaces, or four spaces in Settings."
            ]
        ),
        HelpTopic(
            title: "VoiceOver Settings",
            paragraphs: [
                "VoiceOver Verbosity controls Markdown editing announcements. Off makes no Markdown editing announcements. Light announces list changes, indentation levels, and Insert actions. Full also announces completed Markdown structures as you type.",
                "Heading Swipe Navigation moves between headings in the editor. Swipe right with three fingers for the next heading, or left with three fingers for the previous heading. These gestures are not available while using Braille Screen Input or when assigned to other VoiceOver commands."
            ]
        ),
        HelpTopic(
            title: "Navigating with Outline",
            paragraphs: [
                "Outline lists every markdown heading in document order and identifies its heading level.",
                "Choose a heading to jump directly to that location in the document."
            ]
        ),
        HelpTopic(
            title: "Rendering Documents",
            paragraphs: [
                "Render opens a formatted HTML version of the current document. Headings, lists, links, tables, quotes, code, and tasks retain their document structure.",
                "Done closes the rendered document and returns to the editor."
            ]
        ),
        HelpTopic(
            title: "Sharing and export formats",
            paragraphs: [
                "Open File Actions, choose Share, and select Markdown, Plain Text, HTML, Word Document, PDF, EPUB, eBraille, or Braille Ready Format.",
                "Markdown preserves the original syntax with a .md filename.",
                "Plain Text removes the markdown syntax and leaves readable text with a .txt filename. Level 1 and level 2 headings are underlined, and deeper headings state their level. Lists keep their bullets and numbers, tables become aligned columns, and quoted text begins with a greater-than sign.",
                "HTML creates a complete, rendered web document. Headings, lists, links, tables, quotes, code, and tasks retain their document structure. Text size follows the application the document is opened in.",
                "Word Document converts markdown structure into a .docx file. Handling Word Documents describes what is preserved in each direction.",
                "PDF creates a tagged PDF with fixed pages. Headings, lists, tables, quotes, code, and images are marked as document structure, so a screen reader moves through the document by heading and reads a table cell by cell with its column headings. Pages are US Letter with one-inch margins. A table row stays whole on one page, and a heading stays with the text that follows it.",
                "EPUB creates a reflowable ebook with a table of contents built from the document’s headings. Headings, lists, links, tables, quotes, code, tasks, and images retain their document structure.",
                "eBraille creates a reflowable Unified English Braille document with a .ebrl filename. It includes a table of contents and retains headings, lists, links, tables, quotes, tasks, and images.",
                "For eBraille, select grade 1 or grade 2 and enter the author, producer, copyright date, and whether the export contains the complete document. Enter the date as a year, year and month, or full date, such as 2026, 2026-04, or 2026-04-17.",
                "Additional eBraille details include source work, publisher, rights, subject, description, and education level.",
                "Choose Insert Actions, then Tactile Graphic to attach an SVG, PNG, or JPG and enter its description. An ordinary image has a description, a decorative image has an empty description, and a tactile graphic has a description and the Markdown title tactile.",
                "Braille Ready Format creates fixed-layout Unified English Braille with a .brf filename. Standard layout uses 40 cells by 25 lines. Select Custom to enter another line width and page length. Lists use braille bullets, tables become labeled rows, tasks state Completed or Not completed, and images become labeled descriptions.",
                "Braille Ready Format includes readable link text. Write the address visibly in the markdown when it should also appear in the BRF. eBraille and EPUB retain active links.",
                "Grade 1 is uncontracted Unified English Braille. Grade 2 is contracted Unified English Braille. Code blocks keep their line breaks and spacing and use uncontracted braille.",
                "The app remembers the braille grade, producer name, and last Braille Ready Format layout."
            ]
        ),
        HelpTopic(
            title: "Handling Word Documents",
            paragraphs: [
                "ghostWriter reads and writes Word .docx files by converting between Word’s structure and markdown. Markdown and Word describe documents differently, so a conversion keeps meaning and structure rather than visual appearance.",
                "Importing a Word document brings across headings, paragraphs, bulleted and numbered lists including nested levels and custom starting numbers, tables, block quotes, code blocks, and links. Bold, italic, underline, strikethrough, and inline code are preserved. Underline becomes a <u> tag, because markdown has no underline syntax of its own.",
                "Images in an imported Word document are saved alongside the markdown file and referenced by name. Alternative text is carried across, and images marked decorative in Word import with empty alternative text. An image without alternative text is reported after import so you can add a description.",
                "Footnotes are imported as markdown footnote references with their text collected at the end of the document. Tracked insertions are imported as ordinary text, and tracked deletions are discarded. Comments are not imported.",
                "Exporting to Word converts headings to Word heading styles, so they appear in Word’s Navigation pane and are announced as headings by screen readers. Lists become real Word lists, tables become Word tables with the first row marked as a header row, and block quotes and code blocks receive their own paragraph styles.",
                "Task list items export as text beginning with Completed or Not completed, because Word has no checkbox equivalent in an ordinary paragraph. Horizontal rules are not exported, as markdown’s thematic break has no direct Word counterpart.",
                "Word features with no markdown equivalent are not preserved in either direction. These include fonts, colours, text size, alignment, columns, headers and footers, page breaks, merged table cells, and embedded objects such as charts. A document exported to Word and imported again keeps its structure and text, but not any formatting applied inside Word afterwards.",
                "Import copies Word documents from Files and converts them. File Actions > Share > Word Document exports the document you are editing."
            ]
        ),
        HelpTopic(
            title: "Searching, Sorting, and Document Actions",
            paragraphs: [
                "The library Search field checks document names and contents. The result count updates beneath the field. Activate Clear Search to return to the full library.",
                "Sort changes the field and direction used to arrange documents. Tap a document to open it.",
                "Pin keeps an important document at the beginning of the Library. Pinned documents remain first with every sort option. Last Opened sorts documents by the most recent time they were opened in the editor.",
                "Deleting a folder keeps everything inside it together.",
                "Delete moves a document or folder to Deleted. Restoring returns it to its previous folder when that folder still exists, or to Documents when it does not.",
                "Jump to Line in File Actions moves the cursor to the beginning of a numbered line. Line numbers begin at 1."
            ]
        ),
        HelpTopic(
            title: "Library Gestures",
            paragraphs: [
                "For non-VoiceOver users, swipe left or right on a document or folder to reveal common actions. Touch and hold a document or folder to open its complete actions menu.",
                "On a document, swipe left for Share and Delete. Swipe right for Pin or Unpin. If a download failed, swiping right also provides Retry Download.",
                "On a folder, swipe left for Move and Delete. Swipe right for Rename.",
                "Touch and hold a document for Pin or Unpin, Render, Share, Rename, Move, Duplicate, and Delete. Touch and hold a folder for Rename, Move, and Delete."
            ]
        ),
        HelpTopic(
            title: "Keyboard Shortcuts",
            paragraphs: [
                "Keyboard Shortcuts can be turned on or off under Editing in Settings.",
                "Use Command-N for New, Command-O for Import, and Command-comma for Settings.",
                "While editing, use Command-S for Save Now, Command-F for Find and Replace, Command-R for Render, Command-Shift-O for Outline, Command-Shift-I for Insert, Command-J for Jump to Line, and Command-W to close the editor.",
                "Press Escape to dismiss the editor keyboard."
            ]
        ),
        HelpTopic(
            title: "Inserting Markdown",
            paragraphs: [
                "Insert adds new markdown at the current position or applies compatible formatting and structure to selected text.",
                "Headings create sections using levels 1 through 6. Level 1 is the highest level, and the remaining levels describe subsections.",
                "Link turns text into a destination that can be opened. If text is selected, it becomes the suggested link text.",
                "A link address begins with a scheme, which is the part before the colon that tells iOS what kind of destination to open. Use https://example.com for a secure website, http://example.com for a website without encrypted transport, mailto:name@example.com for email, tel:+15551234567 for a telephone number, or sms:+15551234567 for a text message.",
                "Image from Web inserts an externally hosted image. Provide the image address and alternative text, or leave the alternative text empty when the image is decorative. Image addresses must begin with http:// or https://.",
                "Bold adds strong emphasis. Italic adds ordinary emphasis. Strikethrough marks text as removed or no longer applicable.",
                "Inline Code marks a short piece of code or literal text within a paragraph. Code Block creates a separate preformatted block for multiple lines.",
                "Bulleted List creates an unordered list. Numbered List creates an ordered sequence. Task List creates items that Render identifies as Completed or Not completed.",
                "Table asks for the number of columns and rows. The first row names each column and counts toward the number of rows you choose. Markdown does not have a standard way to identify row headings, so give each row a clear first entry when it needs a label.",
                "Block Quote identifies quoted material. Horizontal Rule adds a thematic break between sections.",
                "Rendering a document that contains an external image may contact the server that hosts that image. ghostWriter does not control the availability or privacy practices of an outside server."
            ]
        )
    ]
}
