import SwiftUI

struct FolderRow: View {
    let folder: LibraryFolder
    let itemCount: Int
    var compilationStatus: LibraryCompilationStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(folder.displayName, systemImage: "folder")
                .font(.headline)
                .foregroundStyle(Color.ghostText)
            if let status = compilationStatus {
                Image(systemName: status.symbol)
                    .foregroundStyle(Color.ghostMuted)
                    .accessibilityHidden(true)
            }
            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(Color.ghostMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(folder.displayName), folder, \(itemCount) \(itemCount == 1 ? "item" : "items")"
                + (compilationStatus.map { ", " + $0.label } ?? "")
        )
    }
}
