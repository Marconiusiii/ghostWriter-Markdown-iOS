import SwiftUI

struct NewLibraryDocumentKey: FocusedValueKey {
    typealias Value = () -> Void
}
extension FocusedValues {
    var newLibraryDocument: (() -> Void)? {
        get { self[NewLibraryDocumentKey.self] }
        set { self[NewLibraryDocumentKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    @FocusedValue(\.newLibraryDocument) private var newDocument
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") { newDocument?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newDocument == nil)
        }
    }
}
