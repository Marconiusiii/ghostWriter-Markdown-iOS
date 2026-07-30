//
//  DocumentAvailability.swift
//  ghostWriter
//
//  Describes whether the current contents of an iCloud document are ready to
//  read on this device. A remote placeholder remains a real library item and
//  must never be mistaken for an empty document.
//

import Foundation

nonisolated enum DocumentAvailability: Equatable, Hashable, Sendable {
    case available
    case checkingICloud
    case waitingForICloud
    case downloading(percent: Int?)
    case updating
    case failed(String)

    var isAvailable: Bool {
        self == .available
    }

    var statusDescription: String? {
        switch self {
        case .available:
            return nil
        case .checkingICloud:
            return "Checking iCloud"
        case .waitingForICloud:
            return "Waiting for iCloud"
        case .downloading(let percent):
            if let percent {
                return "Downloading, \(percent) percent"
            }
            return "Downloading"
        case .updating:
            return "Updating from iCloud"
        case .failed:
            return "Download failed"
        }
    }

    static func iCloudState(
        downloadingStatus: String?,
        isDownloading: Bool,
        percentDownloaded: Double?,
        errorDescription: String?
    ) -> DocumentAvailability {
        if let errorDescription {
            return .failed(errorDescription)
        }

        if isDownloading {
            let percent = percentDownloaded.map {
                min(100, max(0, Int($0.rounded())))
            }
            return .downloading(percent: percent)
        }

        switch downloadingStatus {
        case URLUbiquitousItemDownloadingStatus.current.rawValue:
            return .available
        case URLUbiquitousItemDownloadingStatus.downloaded.rawValue:
            return .updating
        case URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue:
            return .waitingForICloud
        default:
            // iCloud metadata arrives incrementally. A missing status is not
            // proof that the contents are remote, so do not mislabel a local
            // document as waiting for a download.
            return .checkingICloud
        }
    }
}

nonisolated struct ICloudDocumentSnapshot: Equatable, Sendable {
    let url: URL
    let created: Date
    let modified: Date
    let byteCount: Int
    let availability: DocumentAvailability
    let isRecentlyDeleted: Bool
}

nonisolated struct ICloudMetadataRecord: Equatable, Sendable {
    let url: URL
    let created: Date?
    let modified: Date?
    let byteCount: Int?
    let downloadingStatus: String?
    let isDownloading: Bool
    let percentDownloaded: Double?
    let errorDescription: String?
}
