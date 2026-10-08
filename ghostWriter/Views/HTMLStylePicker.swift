import SwiftUI

nonisolated enum HTMLExportStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case ghostWriter

    var id: Self { self }
}

struct HTMLStylePicker: View {
    @Binding var selection: HTMLExportStyle

    var body: some View {
        Picker("HTML style", selection: $selection) {
            Text("Standard").tag(HTMLExportStyle.standard)
            Text(verbatim: "ghostWriter").tag(HTMLExportStyle.ghostWriter)
        }
        .pickerStyle(.menu)
        .accessibilityLabel("HTML style")
    }
}
