//
//  WelcomeView.swift
//  ghostWriter
//
//  A single linear introduction. Explanations precede actions so a screen
//  reader encounters the context before being asked to make a decision.
//

import SwiftUI

struct WelcomeView: View {
    let documentReady: Bool
    let preparationFailed: Bool
    let onExplore: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to ghostWriter Markdown")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.ghostAccent)
                    .accessibilityAddTraits(.isHeader)

                Text("ghostWriter Markdown is an accessible plain-text editor for notes, articles, lists, and more.")

                Text("Markdown uses simple punctuation to create headings, lists, links, emphasis, tables, and other document structure. You can use Insert when you do not want to type the syntax yourself.")

                Text("ghostWriter includes a Welcome document in your Library. Open it to read, edit, and render examples of the Markdown supported by the app.")

                Text("Documents are stored On This Device by default. You can choose optional iCloud Drive syncing later in Settings.")

                if !documentReady && !preparationFailed {
                    ProgressView("Preparing Welcome document")
                } else if preparationFailed {
                    Text("The Welcome document could not be prepared right now. You can continue to the Library, and ghostWriter will try again on a later launch.")
                }

                Button(action: onExplore) {
                    Text("Explore Welcome Document")
                        .frame(maxWidth: .infinity)
                }
                    .ghostProminentButtonStyle()
                    .controlSize(.large)
                    .disabled(!documentReady)

                Button(action: onContinue) {
                    Text("Continue to Library")
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .font(.body)
            .foregroundStyle(Color.ghostText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color.pageBackground)
        .interactiveDismissDisabled()
    }
}
