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

struct EditorFileShortcuts {
    let perform: (EditorFileCommand) -> Void
}

private struct EditorFileShortcutsKey: FocusedValueKey {
    typealias Value = EditorFileShortcuts
}

extension FocusedValues {
    var editorFileShortcuts: EditorFileShortcuts? {
        get { self[EditorFileShortcutsKey.self] }
        set { self[EditorFileShortcutsKey.self] = newValue }
    }
}

struct EditorFileCommands: Commands {
    @FocusedValue(\.editorFileShortcuts) private var shortcuts

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Save Now") { shortcuts?.perform(.save) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(shortcuts == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find and Replace") { shortcuts?.perform(.find) }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(shortcuts == nil)
            Button("Jump to Line…") { shortcuts?.perform(.jump) }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(shortcuts == nil)
        }
    }
}
