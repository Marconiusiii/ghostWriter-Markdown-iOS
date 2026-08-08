import SwiftUI

struct MoveLibraryItemView: View {
    let itemName: String
    let rootDirectory: URL
    let folders: [LibraryFolder]
    let excludedURLs: Set<URL>
    let onMove: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move \(itemName)")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)

            List {
                Button("Documents") {
                    onMove(rootDirectory)
                    dismiss()
                }
                .disabled(excludedURLs.contains(rootDirectory.standardizedFileURL))

                ForEach(validFolders) { folder in
                    Button {
                        onMove(folder.url)
                        dismiss()
                    } label: {
                        Label(relativeName(for: folder.url), systemImage: "folder")
                    }
                }
            }
            .listStyle(.plain)

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color.pageBackground)
    }

    private var validFolders: [LibraryFolder] {
        folders.filter {
            !excludedURLs.contains($0.url.standardizedFileURL)
        }.sorted {
            relativeName(for: $0.url).localizedStandardCompare(
                relativeName(for: $1.url)
            ) == .orderedAscending
        }
    }

    private func relativeName(for url: URL) -> String {
        let root = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
            ? String(path.dropFirst(prefix.count))
            : url.lastPathComponent
    }
}
