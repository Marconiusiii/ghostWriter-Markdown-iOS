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

struct FolderActionsMenu: View {
    let folder: LibraryFolder
    let onRename: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            .accessibilityLabel("Rename \(folder.displayName)")

            Button(action: onMove) {
                Label("Move", systemImage: "folder")
            }
            .accessibilityLabel("Move \(folder.displayName)")

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete \(folder.displayName)")
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Actions for \(folder.displayName)")
    }
}
