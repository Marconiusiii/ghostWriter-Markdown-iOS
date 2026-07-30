//
//  DocumentStorage.swift
//  ghostWriter
//
//  Owns the user's explicit choice between a local library and an iCloud
//  library. The choice is local to this installation: opting in on one device
//  must never upload documents from another device without that user's action.
//

import Foundation
import Observation

enum DocumentStorageChoice: String, CaseIterable, Identifiable {
    case onDevice
    case iCloud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onDevice:
            return "On This Device"
        case .iCloud:
            return "iCloud Drive"
        }
    }
}

enum ICloudAvailability: Equatable {
    case notChecked
    case checking
    case available(URL)
    case unavailable(String)
}

nonisolated enum DocumentStorageResolution: Sendable {
    case available(URL)
    case unavailable(String)
}

/// Converts a file URL into an identity that is stable when the library moves
/// between the local app container and the iCloud ubiquity container.
nonisolated enum DocumentStorageKey {
    static func key(for url: URL) -> String {
        let components = url.standardizedFileURL.pathComponents

        if let deletedIndex = components.lastIndex(of: "Recently Deleted"),
           deletedIndex + 1 < components.count {
            return components[deletedIndex...].joined(separator: "/")
        }

        return url.lastPathComponent
    }
}

@Observable
final class DocumentStorage {
    nonisolated static let containerIdentifier =
        "iCloud.com.marconius.ghostwritermarkdown"

    private(set) var selectedLocation: DocumentStorageChoice
    private(set) var iCloudAvailability: ICloudAvailability = .notChecked

    let localDirectory: URL

    private let defaults: UserDefaults
    private let selectionKey: String
    private let resolveICloudContainer: @Sendable () -> DocumentStorageResolution

    init(
        defaults: UserDefaults = .standard,
        selectionKey: String = "documentStorageLocation",
        localDirectory: URL? = nil,
        resolveICloudContainer: (@Sendable () -> DocumentStorageResolution)? = nil
    ) {
        self.defaults = defaults
        self.selectionKey = selectionKey
        self.localDirectory = localDirectory ?? Self.defaultLocalDirectory()
        self.selectedLocation = defaults.string(forKey: selectionKey)
            .flatMap(DocumentStorageChoice.init(rawValue:)) ?? .onDevice
        self.resolveICloudContainer = resolveICloudContainer ?? {
            let fileManager = FileManager.default
            guard fileManager.ubiquityIdentityToken != nil else {
                return .unavailable(
                    "Sign in to iCloud and turn on iCloud Drive to use syncing."
                )
            }

            guard let container = fileManager.url(
                forUbiquityContainerIdentifier: DocumentStorage.containerIdentifier
            ) else {
                return .unavailable(
                    "ghostWriter could not open its iCloud Drive folder."
                )
            }

            return .available(
                container.appendingPathComponent("Documents", isDirectory: true)
            )
        }
    }

    var activeDirectory: URL? {
        switch selectedLocation {
        case .onDevice:
            return localDirectory
        case .iCloud:
            guard case .available(let directory) = iCloudAvailability else {
                return nil
            }
            return directory
        }
    }

    var statusDescription: String {
        switch selectedLocation {
        case .onDevice:
            return "Documents are stored only on this device."
        case .iCloud:
            switch iCloudAvailability {
            case .notChecked, .checking:
                return "Checking iCloud Drive."
            case .available:
                return "Documents sync with iCloud Drive."
            case .unavailable(let message):
                return message
            }
        }
    }

    @discardableResult
    func prepareCurrentLocation() async -> URL? {
        switch selectedLocation {
        case .onDevice:
            return localDirectory
        case .iCloud:
            return await prepareICloud()
        }
    }

    @discardableResult
    func prepareICloud() async -> URL? {
        if case .available(let directory) = iCloudAvailability {
            return directory
        }

        iCloudAvailability = .checking
        let resolver = resolveICloudContainer
        let result = await Task.detached(priority: .userInitiated) {
            resolver()
        }.value

        switch result {
        case .available(let directory):
            iCloudAvailability = .available(directory)
            return directory
        case .unavailable(let message):
            iCloudAvailability = .unavailable(message)
            return nil
        }
    }

    func select(_ location: DocumentStorageChoice) {
        selectedLocation = location
        defaults.set(location.rawValue, forKey: selectionKey)
    }

    private static func defaultLocalDirectory() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ghostWriter", isDirectory: true)
    }
}
