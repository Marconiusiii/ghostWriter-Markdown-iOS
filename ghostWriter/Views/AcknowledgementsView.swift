import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("ZIPFoundation") {
                    Link(
                        "Project website",
                        destination: URL(string: "https://github.com/weichsel/ZIPFoundation")!
                    )
                    Text(license(named: "ZIPFoundation", fallback: zipFoundationFallback))
                        .textSelection(.enabled)
                }

                Section("liblouis") {
                    Text("Braille translation for eBraille and Braille Ready Format export. Version 3.38.0, built from the upstream release source for iOS.")
                    Link(
                        "Project website",
                        destination: URL(string: "https://github.com/liblouis/liblouis")!
                    )
                    Text("liblouis is free software licensed under the GNU Lesser General Public License, version 2.1 or later. The project website provides the corresponding upstream source. Distribution of an app that statically links this library may require additional materials or permissions; this acknowledgement is not a claim that every distribution obligation is satisfied.")
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
