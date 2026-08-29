//
//  InsertActionsView.swift
//  ghostWriter
//
//  A persistent parent for Markdown insertion categories. Each category opens
//  its own compact sheet, so cancelling a choice returns to this list.
//

import SwiftUI

struct InsertActionsView: View {
    let initialLinkText: String
    let documentURL: URL
    let onInsert: (MarkdownInsertionCommand) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var presentedCategory: InsertCategory?
    @State private var pendingCommand: MarkdownInsertionCommand?
    @State private var lastCategory: InsertCategory?
    @AccessibilityFocusState private var focusedCategory: InsertCategory?

    var body: some View {
        NavigationStack {
            List {
                categoryButton("Headings…", category: .headings)
                categoryButton("Link…", category: .link)
                categoryButton("Image from Files…", category: .fileImage)
                categoryButton("Image from Photo Library…", category: .photoImage)
                categoryButton("Image from Web…", category: .webImage)
                categoryButton("Tactile Graphic…", category: .tactileGraphic)
                categoryButton("Emphasis…", category: .emphasis)
                categoryButton("Code…", category: .code)
                categoryButton("Lists…", category: .lists)
                categoryButton("Table…", category: .table)
                categoryButton("Blocks…", category: .blocks)
            }
            .navigationTitle("Insert Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(item: $presentedCategory, onDismiss: finishCategoryPresentation) { category in
            categoryView(category)
                .presentationDragIndicator(.hidden)
        }
    }

    private func categoryButton(
        _ title: String,
        category: InsertCategory
    ) -> some View {
        Button(title) {
            focusedCategory = nil
            pendingCommand = nil
            lastCategory = category
            presentedCategory = category
        }
        .accessibilityFocused($focusedCategory, equals: category)
    }

    @ViewBuilder
    private func categoryView(_ category: InsertCategory) -> some View {
        switch category {
        case .headings:
            InsertChoiceView(
                title: "Headings",
                choices: (1...6).map {
                    InsertChoice(
                        title: "Heading \($0)",
                        command: .heading(level: $0)
                    )
                },
                onChoose: choose
            )
        case .link:
            MarkdownInsertionView(kind: .link, initialText: initialLinkText) {
                choose(.link(label: $0, address: $1))
            }
        case .fileImage:
            ImageAttachmentInsertionView(
                source: .files,
                documentURL: documentURL
            ) {
                choose(.image(alternativeText: $0, address: $1))
            }
        case .photoImage:
            ImageAttachmentInsertionView(
                source: .photoLibrary,
                documentURL: documentURL
            ) {
                choose(.image(alternativeText: $0, address: $1))
            }
        case .webImage:
            MarkdownInsertionView(kind: .image, initialText: "") {
                choose(.image(alternativeText: $0, address: $1))
            }
        case .tactileGraphic:
            TactileGraphicInsertionView(documentURL: documentURL) {
                choose(.tactileGraphic(description: $0, address: $1))
            }
        case .emphasis:
            InsertChoiceView(
                title: "Emphasis",
                choices: [
                    InsertChoice(title: "Bold", command: .bold),
                    InsertChoice(title: "Italic", command: .italic),
                    InsertChoice(title: "Strikethrough", command: .strikethrough)
                ],
                onChoose: choose
            )
        case .code:
            InsertChoiceView(
                title: "Code",
                choices: [
                    InsertChoice(title: "Inline Code", command: .inlineCode),
                    InsertChoice(title: "Code Block", command: .codeBlock)
                ],
                onChoose: choose
            )
        case .lists:
            InsertChoiceView(
                title: "Lists",
                choices: [
                    InsertChoice(title: "Bulleted List", command: .bulletedList),
                    InsertChoice(title: "Numbered List", command: .numberedList),
                    InsertChoice(title: "Task List", command: .taskList)
                ],
                onChoose: choose
            )
        case .table:
            TableInsertionView {
                choose(.table(columns: $0, rows: $1))
            }
        case .blocks:
            InsertChoiceView(
                title: "Blocks",
                choices: [
                    InsertChoice(title: "Block Quote", command: .blockQuote),
                    InsertChoice(title: "Horizontal Rule", command: .horizontalRule)
                ],
                onChoose: choose
            )
        }
    }

    private func choose(_ command: MarkdownInsertionCommand) {
        pendingCommand = command
    }

    private func finishCategoryPresentation() {
        if let command = pendingCommand {
            pendingCommand = nil
            onInsert(command)
            dismiss()
            return
        }

        guard let lastCategory else { return }
        Task {
            await Task.yield()
            focusedCategory = lastCategory
        }
    }
}

private enum InsertCategory: String, Identifiable, Hashable {
    case headings
    case link
    case fileImage
    case photoImage
    case webImage
    case tactileGraphic
    case emphasis
    case code
    case lists
    case table
    case blocks

    var id: String { rawValue }
}

private struct InsertChoice: Identifiable {
    let title: String
    let command: MarkdownInsertionCommand

    var id: String { title }
}

private struct InsertChoiceView: View {
    let title: String
    let choices: [InsertChoice]
    let onChoose: (MarkdownInsertionCommand) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(choices) { choice in
                Button(choice.title) {
                    onChoose(choice.command)
                    dismiss()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
