//
//  ICloudMigrationView.swift
//  ghostWriter
//
//  A native, explicit confirmation for moving the complete library between
//  local storage and iCloud Drive. The selected location changes only after
//  every source file has been copied and verified.
//

import SwiftUI

private nonisolated enum MigrationAttempt: Sendable {
    case success(DocumentMigrationResult)
    case failure(String)
}

struct ICloudMigrationView: View {
    let destination: DocumentStorageChoice
    let onCompletion: () -> Void

    @Environment(DocumentStorage.self) private var storage
    @Environment(DocumentStore.self) private var store
    @Environment(DocumentLibraryMetadataStore.self) private var libraryMetadata
    @Environment(\.dismiss) private var dismiss

    @State private var isMigrating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Document Storage") {
                    LabeledContent(
                        "Current",
                        value: storage.selectedLocation.label
                    )
                    LabeledContent("New", value: destination.label)
                }

                Section {
                    Text(explanation)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isMigrating {
                    Section {
                        ProgressView("Moving and verifying documents")
                    }
                }

                if let errorMessage {
                    Section("Could Not Change Storage") {
                        Text(errorMessage)
                    }
                }
            }
            .navigationTitle("Change Document Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isMigrating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionLabel) {
                        beginMigration()
                    }
                    .disabled(isMigrating)
                }
            }
        }
        .interactiveDismissDisabled(isMigrating)
    }

    private var explanation: String {
        switch destination {
        case .iCloud:
            return "ghostWriter will move your complete library to iCloud Drive. Documents, renames, edits, and deletions will then sync to your other devices using the same iCloud account. iCloud syncing is not an independent backup."
        case .onDevice:
            return "ghostWriter will move your complete library from iCloud Drive onto this device. After verification, those documents will no longer sync through iCloud."
        }
    }

    private var actionLabel: String {
        switch destination {
        case .iCloud:
            return "Move to iCloud"
        case .onDevice:
            return "Move to This Device"
        }
    }

    private func beginMigration() {
        isMigrating = true
        errorMessage = nil

        Task {
            let targetDirectory: URL?
            switch destination {
            case .iCloud:
                targetDirectory = await storage.prepareICloud()
            case .onDevice:
                targetDirectory = storage.localDirectory
            }

            guard let targetDirectory else {
                isMigrating = false
                if case .unavailable(let message) = storage.iCloudAvailability {
                    errorMessage = message
                } else {
                    errorMessage = "The selected storage location is unavailable."
                }
                return
            }

            let sourceDirectory = store.directory
            let attempt = await Task.detached(priority: .userInitiated) {
                do {
                    return MigrationAttempt.success(
                        try DocumentMigration().migrate(
                            from: sourceDirectory,
                            to: targetDirectory
                        )
                    )
                } catch {
                    return MigrationAttempt.failure(error.localizedDescription)
                }
            }.value

            switch attempt {
            case .success(let result):
                for pair in result.migrated {
                    libraryMetadata.migrateMetadata(
                        from: pair.sourceURL,
                        to: pair.destinationURL
                    )
                    EditorPositionStore.shared.migratePosition(
                        from: pair.sourceURL,
                        to: pair.destinationURL
                    )
                }

                storage.select(destination)
                store.useDirectory(targetDirectory)
                if !result.cleanupFailures.isEmpty {
                    store.lastError = "Document storage changed, but ghostWriter could not remove every old local copy."
                }
                isMigrating = false
                onCompletion()
                dismiss()
            case .failure(let message):
                isMigrating = false
                errorMessage = message
            }
        }
    }
}
