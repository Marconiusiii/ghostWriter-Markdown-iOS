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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
                "Activate New Document in the library, enter a name, and activate Create. The document opens immediately in the Markdown Editor.",
                "Activate Import Document to choose one or more UTF-8 markdown or plain-text files from Files. ghostWriter copies each imported file into its own folder and gives name collisions a safe numbered name.",
                "Activate a document in the library to open it. Documents are ordinary markdown files and keep the name you gave them until you explicitly rename them."
            ]
        ),
        HelpTopic(
            title: "The Markdown Editor",
            paragraphs: [
                "The editor is a standard multiline text field. VoiceOver, braille screen input, dictation, selection, spelling, and hardware keyboards use the system’s normal text-editing behavior.",
                "Markdown punctuation is kept exactly as typed. Smart quotes and smart dashes are disabled so they cannot silently change links, code, or other syntax.",
                "Open File Actions and choose Markdown Reference whenever you need examples of supported syntax."
            ]
        ),
        HelpTopic(
            title: "Saving and the Files App",
            paragraphs: [
                "ghostWriter saves changes automatically after you pause typing and when the app moves into the background. Save Now in File Actions lets you request an immediate save and hear confirmation.",
                "Documents are stored as markdown files in the ghostWriter folder. You can reach that folder through the Files app."
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
                "Outline lists every markdown heading in document order and identifies its heading level. It is designed for quickly navigating long documents without losing your place.",
                "Activate a heading to close the Outline, return to the Markdown Editor, move the insertion point to that heading, scroll it into view, and place VoiceOver focus back in the editor at that location."
            ]
        ),
        HelpTopic(
            title: "Rendering Documents",
            paragraphs: [
                "Activate Render to open a formatted HTML version of the current document. Headings, lists, links, tables, quotes, code, and tasks are represented with real HTML structure.",
                "VoiceOver can navigate the rendered document with familiar web navigation, including the heading and link rotor. Activate Done to return to the editor."
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
                "Sort changes the field and direction used to arrange documents. Each document also provides actions for rendered HTML, sharing, renaming, duplicating, and deleting."
            ]
        ),
        HelpTopic(
            title: "Links and External Images",
            paragraphs: [
                "Open File Actions, choose Insert Markdown, then choose Link or Image from Web. The Link form uses selected text as its starting link text. After insertion, ghostWriter returns the insertion point and VoiceOver focus to the editor.",
                "Rendered links open outside ghostWriter in the appropriate app. Images can use addresses from outside sources through standard markdown image syntax.",
                "Rendering a document that contains an external image may contact the server that hosts that image. ghostWriter does not control the availability or privacy practices of an outside server."
            ]
        ),
        HelpTopic(
            title: "Settings and Accessibility",
            paragraphs: [
                "Settings controls indentation, automatic lists, the editor font, the app appearance, the optional editor Status Bar, and the render sound.",
                "When the Status Bar is enabled, it appears as one focus stop immediately after the editor. Customize Status Bar lets you choose current line and column, document counts, heading level, and selection counts. The status changes quietly and is spoken only when you navigate to it.",
                "All editor font choices follow Dynamic Type, including accessibility text sizes. The interface uses native controls so VoiceOver, Voice Control, Switch Control, and hardware keyboard behavior remain consistent with the rest of iOS."
            ]
        )
    ]
}
