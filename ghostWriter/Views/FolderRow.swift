import SwiftUI

struct FolderRow: View {
    let folder: LibraryFolder
    let itemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(folder.displayName, systemImage: "folder")
                .font(.headline)
                .foregroundStyle(Color.ghostText)
            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(Color.ghostMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(folder.displayName), folder, \(itemCount) \(itemCount == 1 ? "item" : "items")"
        )
    }
}
