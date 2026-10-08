import SwiftUI

nonisolated enum HTMLExportStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case ghostWriter

    var id: Self { self }
}

struct HTMLStylePicker: View {
    @Binding var selection: HTMLExportStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HTML style")
                .accessibilityHidden(true)
            Picker("HTML style", selection: $selection) {
                Text("Standard").tag(HTMLExportStyle.standard)
                Text(verbatim: "ghostWriter").tag(HTMLExportStyle.ghostWriter)
            }
            .pickerStyle(.wheel)
            .accessibilityLabel("HTML style")
        }
    }
}
