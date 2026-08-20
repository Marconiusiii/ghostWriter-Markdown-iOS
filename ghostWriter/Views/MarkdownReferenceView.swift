//
//  MarkdownReferenceView.swift
//  ghostWriter
//
//  A reference for the markdown syntax the editor supports.
//
//  This shows the literal syntax and nothing else. An earlier version tried to
//  describe each example in words — "two tildes around strikethrough" — which
//  told you nothing you could actually type, and offered insert buttons that
//  did not work. On a phone, reading the real characters is the useful thing;
//  the web app's insert-example buttons do not carry over.
//

import SwiftUI

struct MarkdownReferenceView: View {
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

                        ForEach(section.lines) { line in
                            syntaxRow(line)
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

    /// One line of literal syntax. It is selectable so it can be copied, and
    /// left as plain text so VoiceOver reads the actual characters — which is
    /// the entire point of a syntax reference.
    private func syntaxRow(_ line: SyntaxLine) -> some View {
        Text(line.syntax)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(Color.ghostText)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.vertical, 2)
    }
}

struct SyntaxLine: Identifiable {
    let id = UUID()
    let syntax: String
}

struct ReferenceSection: Identifiable {
    let id = UUID()
    let title: String
    let explanation: String
    let lines: [SyntaxLine]

    init(title: String, explanation: String, syntax: [String]) {
        self.title = title
        self.explanation = explanation
        self.lines = syntax.map(SyntaxLine.init(syntax:))
    }

    static let all: [ReferenceSection] = [
        ReferenceSection(
            title: "Headings",
            explanation: "One to six number signs followed by a space. Headings are what make a document navigable, so use them generously.",
            syntax: [
                "# Heading 1",
                "## Heading 2",
                "### Heading 3"
            ]
        ),
        ReferenceSection(
            title: "Lists",
            explanation: "A dash or asterisk for bullets, a number and period for numbered lists. Pressing Return continues the list, and pressing Return on an empty item ends it. Indent two spaces to nest.",
            syntax: [
                "* First bullet",
                "* Second bullet",
                "  * Nested bullet",
                "1. First item",
                "2. Second item",
                "- [ ] Unchecked task",
                "- [x] Completed task"
            ]
        ),
        ReferenceSection(
            title: "Emphasis",
            explanation: "Single markers give italics, double markers give bold, and triple markers combine both. Underlined text uses u tags. Two tildes give strikethrough, and backticks mark inline code.",
            syntax: [
                "*italic*",
                "_italic_",
                "**bold**",
                "__bold__",
                "***bold and italic***",
                "<u>underlined</u>",
                "~~strikethrough~~",
                "`inline code`"
            ]
        ),
        ReferenceSection(
            title: "Links and images",
            explanation: "Square brackets hold link text or an image description, and parentheses hold the address. An image with a description is ordinary. An image with empty brackets is decorative. Add the exact title tactile to mark an SVG, PNG, or JPG as a tactile graphic. Choose Tactile Graphic in Insert Actions to attach one.",
            syntax: [
                "[Marconius](https://marconius.com)",
                "![Alt text](https://example.com/image.jpg)",
                "![](decorative-divider.png)",
                "![Tactile map](map.svg \"tactile\")",
                "[Marconius][home]",
                "[home]: https://marconius.com"
            ]
        ),
        ReferenceSection(
            title: "Quotes and Rules",
            explanation: "Blockquotes begin with a greater-than sign. A horizontal rule is three or more dashes alone on a line.",
            syntax: [
                "> This is a quote",
                ">> Nested quote",
                "---"
            ]
        ),
        ReferenceSection(
            title: "Code Blocks",
            explanation: "Three backticks before and after the code, with an optional language name on the opening fence.",
            syntax: [
                "```swift",
                "let note = \"ghostWriter\"",
                "```"
            ]
        ),
        ReferenceSection(
            title: "Tables",
            explanation: "Pipes between cells, with a divider row of dashes beneath the header. Colons in the divider row set alignment. Screen readers read these as real tables, so headers matter.",
            syntax: [
                "| Feature | Syntax |",
                "| --- | --- |",
                "| Bold | **text** |",
                "| Italic | *text* |"
            ]
        )
    ]
}
