import SwiftUI

struct RenameItemView: View {
    let title: String
    let fieldLabel: String
    @Binding var name: String
    let onCancel: () -> Void
    let onRename: () -> Void
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                VStack(alignment: .leading, spacing: 6) {
                    Text(fieldLabel)
                        .font(.subheadline)
                        .accessibilityHidden(true)
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(fieldLabel)
                }
                Button("Rename", action: onRename)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { nameFieldFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") { nameFieldFocused = false }
                        .accessibilityLabel("Dismiss keyboard")
                }
            }
        }
    }
}
