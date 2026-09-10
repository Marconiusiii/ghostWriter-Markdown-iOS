import SwiftUI

nonisolated enum CompilationTextField: Hashable {
    case outputName, author, producer, copyright, source, publisher, rights, subject, description, education
}

struct CompilationFormatOptions: View {
    @Binding var options: CompilationExportSettings
    var focusedField: FocusState<CompilationTextField?>.Binding

    var body: some View {
        if options.format.supportsPageBreaks || options.format.supportsHeadingOptions {
            Section {
                if options.format.supportsPageBreaks {
                    Toggle("Start each document on a new page", isOn: $options.startsOnNewPages)
                }
                if options.format.supportsHeadingOptions {
                    Toggle("Preserve individual document heading structure", isOn: $options.preservesHeadings)
                    if !options.preservesHeadings {
                        Text("The first document’s title is the only Heading 1. All other headings move down one level.")
                        Text(WordCompilation.headingWarning)
                    }
                }
            }
        }
        switch options.format {
        case .word: EmptyView()
        case .powerPoint:
            Section("Presentation options") {
                Picker("Presentation theme", selection: $options.powerPointTheme) {
                    ForEach(PowerPointTheme.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.menu)
                Picker("Font family", selection: $options.powerPointFont) {
                    ForEach(PowerPointFont.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu)
                Text("Each document starts a new slide. Heading 2 starts additional slides within that document, following the standard PowerPoint export rules.")
            }
        case .eBraille:
            Section("Braille options") {
                Picker("Braille code", selection: $options.eBraille.grade) {
                    ForEach(BrailleGrade.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.menu)
                Text("The selected braille code applies to the whole compilation.")
                field("Author", text: $options.eBraille.creator, id: .author)
                field("Produced by", text: $options.eBraille.transcriber, id: .producer)
                field("Copyright date", text: $options.eBraille.copyrightYear, id: .copyright)
                Text("Use YYYY, YYYY-MM, or YYYY-MM-DD for the copyright date.")
                Toggle("Complete transcription", isOn: $options.eBraille.isCompleteTranscription)
                DisclosureGroup("Additional publication metadata") {
                    field("Source", text: $options.eBraille.source, id: .source)
                    field("Publisher", text: $options.eBraille.publisher, id: .publisher)
                    field("Rights", text: $options.eBraille.rights, id: .rights)
                    field("Subject", text: $options.eBraille.subject, id: .subject)
                    field("Description", text: $options.eBraille.descriptionText, id: .description)
                    field("Education level", text: $options.eBraille.educationLevel, id: .education)
                }
                if let message = options.eBraille.validationMessage { Text(message) }
            }
        case .brf:
            Section("Braille options") {
                Picker("Braille code", selection: $options.brfGrade) {
                    ForEach(BrailleGrade.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.menu)
                Text("The selected braille code applies to the whole compilation.")
                Picker("Use", selection: $options.brfPurpose) {
                    Text("Braille display").tag(BRFWriter.OutputPurpose.brailleDisplay)
                    Text("Embossed Output").tag(BRFWriter.OutputPurpose.embossedPages)
                }.pickerStyle(.menu)
                if options.brfPurpose == .embossedPages {
                    Toggle("Include braille page numbers", isOn: $options.brfPageNumbers)
                }
                Picker("Layout", selection: $options.brfCustomLayout) {
                    Text("Common page, 40 cells by 25 lines").tag(false)
                    Text("Custom braille page").tag(true)
                }.pickerStyle(.menu)
                if options.brfCustomLayout {
                    Picker("Cells per line", selection: $options.brfCells) {
                        ForEach([20, 24, 27, 30, 32, 34, 38, 40, 42], id: \.self) { Text("\($0)").tag($0) }
                    }.pickerStyle(.menu)
                    Picker("Lines per page", selection: $options.brfLines) {
                        ForEach([6, 8, 10, 20, 24, 25, 26, 28, 30], id: \.self) { Text("\($0)").tag($0) }
                    }.pickerStyle(.menu)
                }
                Text("Match the page dimensions to your display or embossing setup. Set paper and margins in your embossing software.")
            }
        case .markdown:
            Section {
                Text("Local images and linked files are included in a ZIP with the Markdown document. Extract the ZIP before opening the Markdown file.")
            }
        default: EmptyView()
        }
    }

    private func field(_ label: String, text: Binding<String>, id: CompilationTextField) -> some View {
        LabeledContent(label) {
            TextField("", text: text)
                .focused(focusedField, equals: id)
                .autocorrectionDisabled()
        }
    }
}
