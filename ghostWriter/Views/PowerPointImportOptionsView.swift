import SwiftUI

struct PowerPointImportOptionsView: View {
    let onImport: (PowerPointImportOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options: PowerPointImportOptions

    init(options: PowerPointImportOptions, onImport: @escaping (PowerPointImportOptions) -> Void) {
        _options = State(initialValue: options)
        self.onImport = onImport
    }

    var body: some View {
        NavigationStack {
            Form {
                Text("Choose what to include and exclude from the import.")
                Section("Include") {
                    Toggle("Slide text", isOn: $options.slideText)
                    Toggle("Tables", isOn: $options.tables)
                    Toggle("Images", isOn: $options.images)
                    Toggle("Speaker notes", isOn: $options.speakerNotes)
                    Toggle("Text formatting", isOn: $options.textFormatting)
                    Toggle("Links", isOn: $options.links)
                    Toggle("Hidden slides", isOn: $options.hiddenSlides)
                }
                Section {
                    DisclosureGroup("Additional options") {
                        Toggle("Decorative images", isOn: $options.decorativeImages)
                            .disabled(!options.images)
                        Toggle("Slide numbers", isOn: $options.slideNumbers)
                        Toggle("Dates", isOn: $options.dates)
                        Toggle("Headers and footers", isOn: $options.footers)
                    }
                }
                Section {
                    Button("Import as Markdown") {
                        onImport(options)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle("PowerPoint Import")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
