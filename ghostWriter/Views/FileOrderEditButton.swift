import SwiftUI

/// Uses the List's native edit mode and reordering behavior.
struct FileOrderEditButton: View {
    @Binding var editMode: EditMode

    var body: some View {
        Button(editMode.isEditing ? "Done Editing" : "Edit") {
            editMode = editMode.isEditing ? .inactive : .active
        }
        .accessibilityLabel(editMode.isEditing ? "Done Editing" : "Edit Document Order")
        .accessibilityInputLabels(editMode.isEditing
            ? ["Done Editing", "Done"]
            : ["Edit", "Edit Files", "Edit Documents", "Edit Document Order", "Edit File Order"])
    }
}
