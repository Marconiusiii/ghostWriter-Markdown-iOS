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
                "New Document creates a named markdown file and opens it for editing.",
                "Import Document copies one or more UTF-8 markdown or plain-text files from Files into ghostWriter. Name conflicts receive a safe numbered name.",
                "Choose any document in the library to open it."
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
            title: "Sharing and Export Formats",
            paragraphs: [
                "Open File Actions, choose Share, and select Markdown, Plain Text, or HTML.",
                "Markdown preserves the original syntax. Plain Text preserves the same text with a .txt filename. HTML creates a complete, rendered web document with a title and semantic main region."
            ]
        ),
        HelpTopic(
            title: "Searching, Sorting, and Document Actions",
            paragraphs: [
                "The library Search field checks document names and contents. The result count updates beneath the field. Activate Clear Search to return to the full library.",
                "Sort changes the field and direction used to arrange documents. Each document also provides actions for rendered HTML, sharing, renaming, duplicating, and deleting.",
                "Jump to Line in File Actions moves the cursor to the beginning of a numbered line. Line numbers begin at 1."
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
                "Bulleted List creates an unordered list. Numbered List creates an ordered sequence. Task List creates items with checked or unchecked states.",
                "Block Quote identifies quoted material. Horizontal Rule adds a thematic break between sections.",
                "Rendering a document that contains an external image may contact the server that hosts that image. ghostWriter does not control the availability or privacy practices of an outside server."
            ]
        )
    ]
}
