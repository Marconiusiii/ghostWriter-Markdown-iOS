//
//  MarkdownReferenceView.swift
//  ghostWriter
//
//  The learning half of ghostWriter, carried over from the web app's reference
//  panel. Each section explains one piece of syntax and offers an example that
//  can be inserted straight into the document.
//
//  DisclosureGroup is used for the sections rather than a hand-built accordion,
//  so expansion state is announced correctly with no extra work.
//

import SwiftUI

struct MarkdownReferenceView: View {
    /// Called with the snippet to insert at the cursor.
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ReferenceSection.all) { section in
                    DisclosureGroup {
                        Text(section.explanation)
                            .font(.body)
                            .foregroundStyle(Color.ghostText)
                            .padding(.vertical, 4)

                        ForEach(section.examples) { example in
                            exampleRow(example)
                        }
                    } label: {
                        Text(section.title)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Markdown Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func exampleRow(_ example: ReferenceExample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(example.syntax)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color.ghostText)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // Read the description rather than spelling out punctuation,
                // which is what a raw syntax string turns into aloud.
                .accessibilityLabel("Example: \(example.spokenSyntax)")

            Button {
                onInsert(example.snippet)
                dismiss()
            } label: {
                Label("Insert \(example.name)", systemImage: "text.insert")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Adds this example at the cursor")
        }
        .padding(.vertical, 4)
    }
}

struct ReferenceExample: Identifiable {
    let id = UUID()
    let name: String
    let syntax: String
    /// How the syntax should be read aloud. Punctuation-heavy markdown is
    /// unintelligible when spoken character by character.
    let spokenSyntax: String
    let snippet: String
}

struct ReferenceSection: Identifiable {
    let id = UUID()
    let title: String
    let explanation: String
    let examples: [ReferenceExample]

    static let all: [ReferenceSection] = [
        ReferenceSection(
            title: "Headings",
            explanation: "Headings use one to six number signs followed by a space. One number sign is the largest heading, six is the smallest. Headings are what make a document navigable, so use them generously.",
            examples: [
                ReferenceExample(
                    name: "Heading",
                    syntax: "# Heading 1",
                    spokenSyntax: "number sign, space, Heading 1",
                    snippet: "# Heading 1"
                ),
                ReferenceExample(
                    name: "Subheading",
                    syntax: "## Heading 2",
                    spokenSyntax: "two number signs, space, Heading 2",
                    snippet: "## Heading 2"
                )
            ]
        ),
        ReferenceSection(
            title: "Lists",
            explanation: "Use a dash or an asterisk for bullet lists, and a number followed by a period for numbered lists. Pressing Return continues the list automatically, and pressing Return on an empty item ends it. Indent by two spaces to nest.",
            examples: [
                ReferenceExample(
                    name: "Bullet List",
                    syntax: "* First bullet\n* Second bullet",
                    spokenSyntax: "asterisk, space, First bullet, then asterisk, space, Second bullet",
                    snippet: "* First bullet\n* Second bullet"
                ),
                ReferenceExample(
                    name: "Numbered List",
                    syntax: "1. First item\n2. Second item",
                    spokenSyntax: "1, period, space, First item, then 2, period, space, Second item",
                    snippet: "1. First item\n2. Second item"
                ),
                ReferenceExample(
                    name: "Task List",
                    syntax: "- [ ] To do\n- [x] Done",
                    spokenSyntax: "dash, space, open bracket, space, close bracket, To do",
                    snippet: "- [ ] To do\n- [x] Done"
                )
            ]
        ),
        ReferenceSection(
            title: "Emphasis",
            explanation: "Wrap text in single markers for italics and double markers for bold. Two tildes give strikethrough, and backticks mark inline code.",
            examples: [
                ReferenceExample(
                    name: "Bold and Italic",
                    syntax: "This is **bold** and *italic*.",
                    spokenSyntax: "double asterisks around bold, single asterisks around italic",
                    snippet: "This is **bold** and *italic* text."
                ),
                ReferenceExample(
                    name: "Strikethrough",
                    syntax: "~~struck through~~",
                    spokenSyntax: "two tildes around struck through",
                    snippet: "~~struck through~~"
                ),
                ReferenceExample(
                    name: "Inline Code",
                    syntax: "`inline code`",
                    spokenSyntax: "backticks around inline code",
                    snippet: "`inline code`"
                )
            ]
        ),
        ReferenceSection(
            title: "Links and Images",
            explanation: "Links use square brackets for the text followed by parentheses for the address. Images are the same with an exclamation mark in front, and the bracketed text becomes the alt text. Always write meaningful alt text.",
            examples: [
                ReferenceExample(
                    name: "Link",
                    syntax: "[Marconius](https://marconius.com)",
                    spokenSyntax: "brackets around Marconius, parentheses around the web address",
                    snippet: "[Marconius](https://marconius.com)"
                ),
                ReferenceExample(
                    name: "Image",
                    syntax: "![Alt text](https://example.com/image.jpg)",
                    spokenSyntax: "exclamation mark, brackets around Alt text, parentheses around the image address",
                    snippet: "![Describe the image here](https://example.com/image.jpg)"
                ),
                ReferenceExample(
                    name: "Reference Link",
                    syntax: "[Marconius][home]\n\n[home]: https://marconius.com",
                    spokenSyntax: "brackets around Marconius, brackets around home, with the address defined separately",
                    snippet: "[Marconius][home]\n\n[home]: https://marconius.com"
                )
            ]
        ),
        ReferenceSection(
            title: "Quotes and Rules",
            explanation: "Blockquotes begin with a greater-than sign. A horizontal rule is three or more dashes on a line of their own.",
            examples: [
                ReferenceExample(
                    name: "Blockquote",
                    syntax: "> This is a quote",
                    spokenSyntax: "greater-than sign, space, This is a quote",
                    snippet: "> This is a quote"
                ),
                ReferenceExample(
                    name: "Horizontal Rule",
                    syntax: "---",
                    spokenSyntax: "three dashes",
                    snippet: "---"
                )
            ]
        ),
        ReferenceSection(
            title: "Code Blocks",
            explanation: "Fenced code blocks use three backticks before and after the code. You can name the language on the opening fence.",
            examples: [
                ReferenceExample(
                    name: "Code Block",
                    syntax: "```swift\nlet note = \"ghostWriter\"\n```",
                    spokenSyntax: "three backticks, swift, the code, then three backticks",
                    snippet: "```swift\nlet note = \"ghostWriter\"\n```"
                )
            ]
        ),
        ReferenceSection(
            title: "Tables",
            explanation: "Tables use pipes between cells, with a divider row of dashes beneath the header. Colons in the divider row set column alignment. Tables are read by screen readers as real tables, so headers matter.",
            examples: [
                ReferenceExample(
                    name: "Table",
                    syntax: "| Feature | Syntax |\n| --- | --- |\n| Bold | **text** |",
                    spokenSyntax: "pipes separating Feature and Syntax, a divider row of dashes, then the rows",
                    snippet: "| Feature | Syntax |\n| --- | --- |\n| Bold | **text** |\n| Italic | *text* |"
                )
            ]
        )
    ]
}
