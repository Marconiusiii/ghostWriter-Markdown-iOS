//
//  WhyGhostWriterView.swift
//  ghostWriter
//
//  The story behind the original web editor and its mischievous rendering.
//

import SwiftUI

struct WhyGhostWriterView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("I originally built the web version of ghostWriter as a fun little prank. It started off as an innocent markdown editor; a simple text area, a rendered output section below it, code references, just a nice, unsuspecting experience.")

                    Text("As victims...er...users practiced their markdown, they'd press the render button to check out how the HTML structure was being formed. Yet every time they went to inspect the rendered output, things would be off.")

                    Text("A word misspelled here and there, some transposed or switched. They'd go back up into their code and find the errors and go fix them. Hitting render again would cause even more spooky mayhem to happen. New words appearing, words getting duplicated, even little ghost emojis popping up here and there. Each render caused even more chaos!")

                    Text("Eventually I actually turned it into a real markdown editor and education system that I used for students to utilize during a Markdown class I taught, and left the spookiness as a setting that could be turned on in the settings.")

                    Text("I've left out the ghosts for now in this iOS version, but who knows, they may haunt it in the future!")

                    loreLink(
                        "Spooky Original ghostWriter",
                        destination: "https://marconius.com/fun/gw/"
                    )

                    loreLink(
                        "ghostWriter Proper on the Web",
                        destination: "https://marconius.com/fun/ghostWriter/"
                    )
                }
                .font(.body)
                .foregroundStyle(Color.ghostText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color.pageBackground)
            .navigationTitle("Why ghostWriter?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }

    private func loreLink(
        _ title: String,
        destination: String
    ) -> some View {
        Link(title, destination: URL(string: destination)!)
            .accessibilityAddTraits(.isLink)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityHint("Opens in external browser")
    }
}
