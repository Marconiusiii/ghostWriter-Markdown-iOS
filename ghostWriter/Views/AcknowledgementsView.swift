import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("ZIPFoundation") {
                    Link(
                        "Project Website",
                        destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!
                    )
                    Text(licenseText)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Acknowledgements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }

    private var licenseText: String {
        let bundledURL = Bundle.main.url(
            forResource: "ZIPFoundation",
            withExtension: "txt",
            subdirectory: "Licenses"
        ) ?? Bundle.main.url(forResource: "ZIPFoundation", withExtension: "txt")
        guard let bundledURL,
              let text = try? String(contentsOf: bundledURL, encoding: .utf8) else {
            return "ZIPFoundation is available under the MIT License."
        }
        return text
    }
}
