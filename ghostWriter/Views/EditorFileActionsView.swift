import SwiftUI

enum EditorFileCommand {
    case rename, reference, find, jump, language, save, inclusion, duplicate
    case share(EditorView.EditorShareFormat)
}

struct EditorFileActionsView: View {
    let isHelpManual: Bool
    let saving: Bool
    let inclusionLabel: String?
    let onSelect: (EditorFileCommand) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !isHelpManual {
                    Button("Rename Document") { onSelect(.rename) }
                }
                Button("Markdown Reference") { onSelect(.reference) }
                Button("Find and Replace") { onSelect(.find) }
                Button("Jump to Line…") { onSelect(.jump) }
                if !isHelpManual {
                    Button("Document Language…") { onSelect(.language) }
                }
                Button("Save Now") { onSelect(.save) }
                    .disabled(saving)
                if !isHelpManual, let inclusionLabel {
                    Button(inclusionLabel) { onSelect(.inclusion) }
                }
                NavigationLink("Share") {
                    List(EditorView.EditorShareFormat.allCases) { format in
                        Button(format.label) { onSelect(.share(format)) }
                    }
                    .navigationTitle("Share")
                    .navigationBarTitleDisplayMode(.inline)
                }
                if !isHelpManual {
                    Button("Duplicate") { onSelect(.duplicate) }
                }
            }
            .navigationTitle("File Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

enum EditorFileShortcutRequest: Equatable {
    case idle, save, find, jump

    var command: EditorFileCommand? {
        switch self {
        case .idle: nil
        case .save: .save
        case .find: .find
        case .jump: .jump
        }
    }
}

private struct EditorFileShortcutsKey: FocusedValueKey {
    typealias Value = Binding<EditorFileShortcutRequest>
}

extension FocusedValues {
    var editorFileShortcuts: Binding<EditorFileShortcutRequest>? {
        get { self[EditorFileShortcutsKey.self] }
        set { self[EditorFileShortcutsKey.self] = newValue }
    }
}

struct EditorFileCommands: Commands {
    @FocusedBinding(\.editorFileShortcuts) private var shortcutRequest

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Save Now") { shortcutRequest = .save }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(shortcutRequest == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find and Replace") { shortcutRequest = .find }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(shortcutRequest == nil)
            Button("Jump to Line…") { shortcutRequest = .jump }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(shortcutRequest == nil)
        }
    }
}
