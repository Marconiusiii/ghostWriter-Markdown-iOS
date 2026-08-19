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
                    Text(license(named: "ZIPFoundation", fallback: zipFoundationFallback))
                        .textSelection(.enabled)
                }

                Section("liblouis") {
                    Text("Braille translation for eBraille export. Version 3.38.0, used unmodified.")
                    Link(
                        "Project Website",
                        destination: URL(string: "https://github.com/liblouis/liblouis")!
                    )
                    // The LGPL requires that the library's source be available
                    // to anyone who receives the app. liblouis is a public
                    // project, so naming the version and linking upstream is
                    // what satisfies that.
                    Text("liblouis is free software licensed under the GNU Lesser General Public License, version 2.1 or later. It is used here without modification, and its complete source is available from the project website above.")
                        .textSelection(.enabled)
                    Text(license(named: "liblouis", fallback: liblouisFallback))
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

    private let zipFoundationFallback = "ZIPFoundation is available under the MIT License."

    private let liblouisFallback = "liblouis is available under the GNU Lesser General Public License, version 2.1 or later."

    private func license(named name: String, fallback: String) -> String {
        let bundledURL = Bundle.main.url(
            forResource: name,
            withExtension: "txt",
            subdirectory: "Licenses"
        ) ?? Bundle.main.url(forResource: name, withExtension: "txt")
        guard let bundledURL,
              let text = try? String(contentsOf: bundledURL, encoding: .utf8) else {
            return fallback
        }
        return text
    }
}
