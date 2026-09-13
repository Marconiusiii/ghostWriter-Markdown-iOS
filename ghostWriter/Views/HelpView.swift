import SwiftUI
import UIKit

struct HelpView: View {
    var onOpenHelpManual: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button("ghostWriter Help Manual") {
                    onOpenHelpManual()
                    dismiss()
                }
                    .accessibilityLabel("ghostWriter Help Manual")
                ForEach(HelpCategory.all) { category in
                    NavigationLink {
                        HelpCategoryView(category: category)
                    } label: {
                        Text(category.title)
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

private struct HelpCategoryView: View {
    let category: HelpCategory

    var body: some View {
        List(category.topics) { topic in
            if category.topics.count == 1 {
                topicContent(topic)
            } else {
                DisclosureGroup {
                    topicContent(topic)
                } label: {
                    Text(topic.title)
                        .font(.headline)
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func topicContent(_ topic: HelpTopic) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(topic.paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(Color.ghostText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(topic.subtopics) { subtopic in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(subtopic.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .textSelection(.enabled)
                                .font(.body)
                                .foregroundStyle(Color.ghostText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if subtopic.offersStylesheetCopy {
                            Button("Copy JSON to Clipboard") {
                                UIPasteboard.general.string = WordExportHelp.example
                                UIAccessibility.post(notification: .announcement, argument: String(localized: "JSON copied to clipboard."))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(subtopic.title)
                        .font(.headline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HelpTopic: Identifiable {
    let title: String
    let paragraphs: [String]
    var subtopics: [HelpTopic] = []
    var offersStylesheetCopy = false
    var id: String { title }
}

struct HelpCategory: Identifiable {
    let title: String
    let topics: [HelpTopic]
    var id: String { title }

    static let all: [HelpCategory] = [
        HelpCategory(
            title: "Markdown and writing",
            topics: [
                HelpTopic(
                    title: "Getting started with Markdown",
                    paragraphs: [
                        "Markdown lets you write a formatted document using plain text. You type simple punctuation marks for headings, lists, and emphasis, then use Render to read the formatted result.",
                        "Press Return twice to start a new paragraph. This leaves one empty line between paragraphs. Lines without an empty line separating them will get parsed as a single paragraph when rendered or exported.",
                        "Begin a heading with a number sign and a space, such as # My title. Use ## for a subsection and ### for a section within it. Heading levels run from 1 to 6 and give your document a structure readers can navigate.",
                        "Put **two asterisks** around bold text or *one asterisk* around italic text. Begin a bulleted item with a hyphen and a space, or a numbered item with 1. and a space. The Insert feature can add formatting for you when working in the Editor.",
                        "Open File Actions > Markdown Reference in the editor for explanations and examples you can copy, including links, images, tables, and code."
                    ]
                ),
                HelpTopic(
                    title: "Creating and opening documents",
                    paragraphs: [
                        "Choose New in the Library to create a document. Depending on When Starting a New Document in Settings, you will be asked for a name or the document will use today’s date. Choose a document in the Library to open it.",
                        "Choose New Folder to create a folder in your current location. Open a folder to work inside it, and use Back to return to its parent.",
                        "Import copies Markdown, plain-text, Word, or PowerPoint files from Files into your current folder. Word and PowerPoint documents are converted to Markdown. If a name is already in use, the copy receives a numbered name. See the format-specific topics for conversion options and limitations."
                    ]
                ),
                HelpTopic(
                    title: "Writing and editing",
                    paragraphs: [
                        "Write and revise your Markdown in the editor. File Actions provides saving, sharing, Find and Replace, Jump to Line, and the Markdown Reference.",
                        "Use Insert to add formatting at the cursor or apply supported formatting to selected text. For a link, selected text becomes the suggested link text. Enter a destination such as https://example.com or mailto:name@example.com.",
                        "Headings organize sections; lists organize related items or steps. Use a block quote for quoted material, inline code for short literal text, and a code block for several preformatted lines. A horizontal rule marks a thematic break.",
                        "Table asks for the number of columns and rows. The first row contains column headings and counts toward the number of rows. Give each row a clear first entry if it needs a label.",
                        "Choose Jump to Line in File Actions, enter a line number starting at 1, and choose Jump to place the cursor at that line."
                    ]
                ),
                HelpTopic(
                    title: "Lists and indentation",
                    paragraphs: [
                        "When Automatic Lists is enabled, pressing Return after a bullet, numbered item, or task continues that list. Press Return on an empty list item to end the list.",
                        "Use Indent and Outdent above the on-screen keyboard to change the nesting level of the current line or selected lines. Choose tabs, two spaces, or four spaces in Settings > Editing."
                    ]
                ),
                HelpTopic(
                    title: "Outline and formatted preview",
                    paragraphs: [
                        "Outline lists your headings in document order and identifies their levels. Choose a heading to move to that part of the document.",
                        "Render opens a formatted HTML preview. Use it to read your work with its headings, paragraphs, lists, and other formatting applied. Choose Done to return to the editor."
                    ]
                ),
                HelpTopic(
                    title: "Images and descriptions",
                    paragraphs: [
                        "Choose Insert, then Image from Files or Image from Photo Library to attach a picture. Enter alternative text describing what the image communicates, or mark it decorative if it adds no information. The image is stored with the document and referenced in its Markdown.",
                        "Image from Web inserts a link to an image at an http:// or https:// address. Rendering may contact that website to load the image, and the image remains dependent on its availability.",
                        "Choose Tactile Graphic for an SVG, PNG, or JPG prepared for tactile presentation. Supply a description so readers can understand its purpose."
                    ]
                )
            ]
        ),
        HelpCategory(
            title: "Library and storage",
            topics: [
                HelpTopic(
                    title: "Saving and storage",
                    paragraphs: [
                        "ghostWriter saves automatically after you pause typing and when the app moves into the background. Choose Save Now in File Actions to request an immediate save.",
                        "Your documents are ordinary Markdown files in the ghostWriter folder, which you can also open in Files. Settings > Files > Document Storage chooses on-device or iCloud storage. Follow the prompts when changing locations.",
                        "Files can be accessed through whatever storage apps you have available through the iOS Files app, so OneDrive, Google Drive, Dropbox, and more can be used. Files imported from there will be copied into the currently selected ghostWriter storage location, either iCloud or on-device."
                    ]
                ),
                HelpTopic(
                    title: "Finding and organizing documents",
                    paragraphs: [
                        "Search in the Library checks document names and contents.",
                        "Use Sort to choose Sort By and Sort Order. The Library and each folder remember their own sorting choices. Last Opened sorts by when documents were most recently opened in the editor.",
                        "Choose Manual sorting to arrange items yourself. With Search cleared and at least two items available, choose Edit, move items with the reorder controls, then choose Done Editing. Folders and unpinned documents can be arranged together.",
                        "Pin keeps documents at the beginning of the document group. In Manual order, pinned documents can be reordered within their own group. Pinning does not affect compilation exports.",
                        "Touch and hold a file or folder to open its actions, or use its VoiceOver Actions. These include renaming, moving, and deleting; files also offer actions such as duplication and sharing.",
                        "Delete moves an item to Deleted. Restore returns it to its previous folder if that folder still exists, or to Documents otherwise. Deleting and restoring a folder keeps its contents together. Permanent deletion cannot be undone."
                    ]
                ),
                HelpTopic(
                    title: "Folder statistics",
                    paragraphs: [
                        "Use Total Word Count to check the length of a folder’s Markdown documents, including nested folders. Totals include words, sentences, characters, and the number of documents counted. Saved compilation exclusions also exclude files and folders from all these totals. Find it in the folder’s context menu or accessibility actions, or in its heading actions when the folder is open.",
                        "The result reports words, sentences, characters, and documents counted out of all Markdown documents in the folder and nested folders. Words use the same count as the editor; characters include Markdown marks, spaces, and line breaks. Sentences use automatic language analysis of the source; headings and list fragments can count as sentences.",
                        "Progress appears while documents are read or downloaded. If a file cannot be read, the result is marked Partial total and identifies the omitted files. Cancel stops the count."
                    ]
                ),
                HelpTopic(
                    title: "Touch gestures",
                    paragraphs: [
                        "Without VoiceOver, swipe on Library items to reveal common actions. Swipe left on a document for Share and Delete, or right for Pin or Unpin. A failed download also offers Retry Download.",
                        "For folders, swipe left for Move and Delete, or right for Rename. Touch and hold either kind of item for its full actions menu."
                    ]
                )
            ]
        ),
        HelpCategory(
            title: "Accessibility and Settings",
            topics: [
                HelpTopic(
                    title: "VoiceOver",
                    paragraphs: [
                        "Settings > VoiceOver Settings contains Verbosity and Heading Swipe Navigation. VoiceOver Verbosity controls Markdown editing announcements. Off makes no Markdown editing announcements. Light announces list changes, indentation levels, and Insert actions. Full also announces completed Markdown structures as you type.",
                        "Heading Swipe Navigation moves between headings in the editor. Swipe right with three fingers for the next heading, or left with three fingers for the previous heading. These gestures are not available while using Braille Screen Input or when assigned to other VoiceOver commands.",
                        "Use VoiceOver Actions on Library files and folders to reach their available commands. An open folder’s heading also offers folder actions."
                    ]
                ),
                HelpTopic(
                    title: "Keyboard shortcuts",
                    paragraphs: [
                        "Enable Keyboard Shortcuts under Editing in Settings to use the app’s hardware keyboard commands.",
                        "In the Library, Command-N creates a document, Command-O imports files, and Command-comma opens Settings.",
                        "In the editor, use Command-S for Save Now, Command-F for Find and Replace, Command-R for Render, Command-Shift-O for Outline, Command-Shift-I for Insert, Command-J for Jump to Line, and Command-W to close the editor.",
                        "Press Escape to dismiss the editor keyboard."
                    ]
                ),
                HelpTopic(
                    title: "Settings",
                    paragraphs: [
                        "When App Opens chooses whether to begin in the Library, a new document, or your last document. When Starting a New Document chooses whether to ask for a name or use today’s date.",
                        "Editing contains Indentation, Automatic Lists, and Keyboard Shortcuts. VoiceOver Settings controls editing feedback and heading navigation; see VoiceOver for details.",
                        "Appearance contains Theme and Editor Font. Status Bar displays document information below the editor; Customize Status Bar chooses what it shows. Render Sound plays when rendering and follows the device’s silent switch.",
                        "Export contains Use smart punctuation and Thematic separator. Choose a Word stylesheet in the Word export flow. Their Help topics explain what they change. Edit defaults under eBraille metadata supplies information for new exports."
                    ]
                )
            ]
        ),
        HelpCategory(
            title: "Sharing and compilations",
            topics: [
                HelpTopic(
                    title: "Sharing a document",
                    paragraphs: [
                        "In the editor, choose File Actions > Share, then an export format. When the output is ready, choose an app or Save to Files from the Share Sheet. Library file actions also offer sharing.",
                        "Choose Markdown to continue editing the source, Plain Text for text without Markdown marks, HTML for a web document, Word Document for a Word file, or PDF for fixed pages. EPUB is a reflowable ebook, PowerPoint is a presentation, and eBraille and Braille Ready Format provide braille output.",
                        "To combine several documents into one output, use Export Compilation… on their folder. The following topics explain compilation choices and the details of each format."
                    ]
                ),
                HelpTopic(
                    title: "Compilation Export",
                    paragraphs: CompilationHelp.paragraphs
                ),
                HelpTopic(
                    title: "Smart punctuation in exports",
                    paragraphs: CompilationHelp.smartPunctuation
                ),
                HelpTopic(
                    title: "Text, PDF, and ebook formats",
                    paragraphs: [
                        "Markdown retains editable Markdown syntax. A compilation combines the sources into normalized Markdown, which can change syntax and spacing. If assets are included in a ZIP, extract it and keep the files together.",
                        "Plain Text removes Markdown syntax while retaining readable structure. Level 1 and 2 headings are underlined, deeper headings state their level, lists keep bullets and numbers, and tables become aligned columns.",
                        "Settings > Export > Thematic separator replaces Markdown thematic breaks with your chosen decoration in Plain Text and Word exports. None omits them. Plain Text centers the characters with spaces within 72 columns; their appearance depends on the font and app used to read the file.",
                        "HTML preserves document structure, embeds supported attached images, and retains image descriptions. Its text size follows the app used to open it.",
                        "PDF produces tagged, fixed pages with headings, lists, tables, and image descriptions. Pages use US Letter with one-inch margins. Headings stay with the following text, and table rows stay together.",
                        "EPUB produces a reflowable ebook with heading navigation and active links. For braille publications, see Braille exports."
                    ]
                )
            ]
        ),
        HelpCategory(
            title: "Word and Powerpoint",
            topics: [
                HelpTopic(
                    title: "Importing Word documents",
                    paragraphs: [
                        "Choose Import in the Library and select a .docx file. ghostWriter converts it into a Markdown copy. Review the converted document before continuing: Markdown preserves structure but cannot reproduce every Word feature.",
                        "Importing a Word document brings across headings, paragraphs, bulleted and numbered lists including nested levels and custom starting numbers, tables, block quotes, code blocks, and links. Bold, italic, underline, strikethrough, and inline code are preserved. Underline becomes a <u> tag, because markdown has no underline syntax of its own.",
                        "Images in an imported Word document are saved alongside the markdown file and referenced by name. Alternative text is carried across, and images marked decorative in Word import with empty alternative text. An image without alternative text is reported after import so you can add a description.",
                        "Footnotes are imported as markdown footnote references with their text collected at the end of the document. Tracked insertions are imported as ordinary text, and tracked deletions are discarded. Comments are not imported.",
                        "Fonts, colors, text size, alignment, columns, headers and footers, page breaks, merged table cells, and embedded objects such as charts are not retained."
                    ]
                ),
                HelpTopic(
                    title: "Word Export",
                    paragraphs: WordExportHelp.workflow
                ),
                HelpTopic(
                    title: "Word Stylesheet",
                    paragraphs: WordExportHelp.theme,
                    subtopics: [
                        HelpTopic(
                            title: "Word Stylesheet reference",
                            paragraphs: WordExportHelp.reference + WordExportHelp.advanced,
                            offersStylesheetCopy: true
                        )
                    ]
                ),
                HelpTopic(
                    title: "PowerPoint import",
                    paragraphs: [
                        "Choose Import and select one or more .pptx presentations from Files. Choose the content to include, then activate Import as Markdown. Each presentation becomes a separate document in the current folder. The original files are unchanged.",
                        "Slide text, tables, images, speaker notes, text formatting, and links are included by default. Hidden slides are excluded. Additional options include decorative images, slide numbers, dates, and headers and footers. Your choices are remembered and apply to every presentation in the selected batch.",
                        "Turning off Slide text omits body paragraphs and lists but keeps slide headings. Turning off Text formatting keeps the words without emphasis. Turning off Links keeps the link text without its destination. Turning off Images omits pictures and their references. For notes-only import, turn off Slide text, Tables, and Images while leaving Speaker notes on.",
                        "Slide titles become level 2 headings. A first slide identified as a title slide becomes a level 1 heading instead. Untitled slides use Slide followed by their original slide number. Repeated titles remain separate sections. Speaker notes follow three asterisks on a line by themselves.",
                        "Bulleted and numbered lists retain their structure and nesting. Ordinary tables become markdown tables; tables with merged cells become labeled text rows. Text formatting includes bold, italic, underline, and strikethrough. Supported web and email links remain active. Internal slide links become plain text.",
                        "Embedded PNG, JPEG, and safe SVG pictures are saved with the markdown document using relative references. Existing alternative text is retained. Missing descriptions are reported after import. Unsupported or unavailable images keep their descriptions when available. Linked external images are not downloaded.",
                        "Slides follow presentation order. Objects follow their stored order, with grouped objects kept together. Visually arranged columns may need editing afterward. Fonts, colors, exact layout, animations, and transitions are not retained. Charts, SmartArt, equations, audio, video, and embedded objects are not converted into editable equivalents. Available descriptions are retained for unsupported objects.",
                        "Presentations up to 512 MiB per file are supported. Turn off Images before activating Import as Markdown to skip loading and extracting pictures. The original presentation is unchanged. Images have a separate size allowance from slide text and notes; pictures that exceed image limits are omitted with a notice.",
                        "Legacy .ppt files and password-protected presentations are not supported. Other limits include 500 slides and 4,096 internal files and folders. When a size or complexity limit is reached, the message identifies that limit. Invalid presentations do not create a markdown document; other valid files in the batch can still import."
                    ]
                ),
                HelpTopic(
                    title: "PowerPoint export",
                    paragraphs: [
                        "PowerPoint creates a widescreen .pptx presentation. A level 1 heading before the first slide titles the presentation. Content before the first level 2 heading appears on the title slide. Each level 2 heading begins and titles a new slide. Deeper headings and paragraphs become slide text. Put three asterisks on a line by themselves to begin speaker notes, which continue until the next level 2 heading.",
                        "PowerPoint keeps bulleted and numbered lists, including nested levels. Task lists become list items beginning with Completed or Not completed, not interactive checkboxes. Links remain clickable, including links inside table cells. Quotes become paragraphs introduced by Quote, and code blocks become monospaced text without syntax highlighting.",
                        "PowerPoint tables become editable tables with a header row. Column alignment, supported text formatting, and links are retained. Tables use the selected theme, and text wraps inside cells. Tables and surrounding text stay in Markdown order. Images referenced inside cells appear as separate slide pictures. Tables in speaker notes remain labeled text rows.",
                        "PowerPoint includes attached images from Files or the Photo Library and PNG, JPEG, or SVG images linked with HTTPS addresses. Images retain their alternative text. SVG images become high-resolution PNG pictures, preserving their colors and transparency. Unavailable, invalid, or oversized images are skipped while the rest of the presentation exports.",
                        "PowerPoint allows up to four included images per slide. If a slide contains too much text, too many images, or a table that is too wide or tall, divide the content with another level 2 heading. Tables keep readable text sizes. The exporter does not automatically split crowded slides.",
                        "Choose Presentation theme and Font family to set the presentation’s appearance. These choices are remembered for future exports. Themes affect slide backgrounds, text, and links; image colors are unchanged."
                    ]
                )
            ]
        ),
        HelpCategory(
            title: "Braille exports",
            topics: [
                HelpTopic(
                    title: "Braille exports",
                    paragraphs: [
                        "Choose eBraille for a reflowable braille publication with heading navigation and active links, or Braille Ready Format for fixed-layout braille. The output filenames end in .ebrl and .brf respectively.",
                        "For eBraille, select grade 1 or grade 2 and enter the author, producer, copyright date, and whether the export contains the complete document. Enter the date as a year, year and month, or full date, such as 2026, 2026-04, or 2026-04-17.",
                        "Additional eBraille details include source work, publisher, rights, subject, description, and education level.",
                        "Braille Ready Format creates fixed-layout Unified English Braille with a .brf filename. Choose Braille display or Emboss on paper. Common page uses 40 cells by 25 lines. Select Custom braille page to choose another number of cells and lines. Lists use braille bullets, tables become labeled rows, tasks state Completed or Not completed, and images become labeled descriptions.",
                        "For embossed pages, Include braille page numbers places each number at the bottom right and reserves the final line. Turn it off to use every selected line for document content. Set paper size, physical margins, binding margins, and single-sided or interpoint output in the embossing software.",
                        "Braille Ready Format writes a link label followed by its address in parentheses. A link whose label is already the address appears once. Internal document links include the link text without the fragment address. eBraille and EPUB retain active links.",
                        "Grade 1 is uncontracted Unified English Braille. Grade 2 is contracted Unified English Braille. Code blocks keep their line breaks and spacing and use uncontracted braille.",
                        "The app remembers your braille grade, producer name, and last Braille Ready Format layout. A compilation uses one selected braille code for the entire output, including documents whose source languages differ. Page numbering continues across the combined BRF output."
                    ]
                )
            ]
        )
    ]
}
