import SwiftUI

struct WordExportHelpView: View {
    var body: some View {
        List {
            Section("Word export and compilation") {
                ForEach(WordExportHelp.workflow, id: \.self) { Text($0) }
            }
            Section("JSON style sheets") {
                ForEach(WordExportHelp.theme, id: \.self) { Text($0) }
                Text(WordExportHelp.example).font(.body.monospaced()).textSelection(.enabled)
            }
        }
        .navigationTitle("Word Export Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}
