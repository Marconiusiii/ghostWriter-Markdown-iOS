import SwiftUI

struct NewFolderView: View {
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)

            TextField("Folder Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Create") {
                    onCreate(name)
                    dismiss()
                }
                .ghostProminentButtonStyle()
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.pageBackground)
    }
}
