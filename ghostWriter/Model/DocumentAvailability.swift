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
    case waitingToUpload
    case uploading(percent: Int?)
    case uploadFailed(String)
    case waitingForICloud
    case downloading(percent: Int?)
    case updating
    case failed(String)

    var isAvailable: Bool {
        switch self {
        case .available, .waitingToUpload, .uploading, .uploadFailed:
            return true
        case .waitingForICloud, .downloading, .updating, .failed:
            return false
        }
    }

    var reportsUploadState: Bool {
        switch self {
        case .waitingToUpload, .uploading, .uploadFailed:
            return true
        default:
            return false
        }
    }

    var statusDescription: String? {
        switch self {
        case .available:
            return nil
        case .waitingToUpload:
            return "Waiting to Upload"
        case .uploading(let percent):
            if let percent {
                return "Uploading to iCloud, \(percent) percent"
            }
            return "Uploading to iCloud"
        case .uploadFailed(let message):
            return "Upload failed. \(message)"
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
        errorDescription: String?,
        isUploaded: Bool? = nil,
        isUploading: Bool = false,
        percentUploaded: Double? = nil,
        uploadErrorDescription: String? = nil
    ) -> DocumentAvailability {
        if let uploadErrorDescription {
            return .uploadFailed(uploadErrorDescription)
        }

        if isUploading {
            return .uploading(
                percent: normalizedPercent(percentUploaded)
            )
        }

        if isUploaded == false {
            return .waitingToUpload
        }

        if let errorDescription {
            return .failed(errorDescription)
        }

        if isDownloading {
            return .downloading(
                percent: normalizedPercent(percentDownloaded)
            )
        }

        switch downloadingStatus {
        case URLUbiquitousItemDownloadingStatus.current.rawValue:
            return .available
        case URLUbiquitousItemDownloadingStatus.downloaded.rawValue:
            return .updating
        case URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue:
            return .waitingForICloud
        default:
            // iCloud metadata arrives incrementally. Only an explicit
            // not-downloaded status proves that contents are remote.
            return .available
        }
    }

    private static func normalizedPercent(_ value: Double?) -> Int? {
        value.map {
            min(100, max(0, Int($0.rounded())))
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
    let isUploaded: Bool?
    let isUploading: Bool
    let percentUploaded: Double?
    let uploadErrorDescription: String?

    init(
        url: URL,
        created: Date?,
        modified: Date?,
        byteCount: Int?,
        downloadingStatus: String?,
        isDownloading: Bool,
        percentDownloaded: Double?,
        errorDescription: String?,
        isUploaded: Bool? = nil,
        isUploading: Bool = false,
        percentUploaded: Double? = nil,
        uploadErrorDescription: String? = nil
    ) {
        self.url = url
        self.created = created
        self.modified = modified
        self.byteCount = byteCount
        self.downloadingStatus = downloadingStatus
        self.isDownloading = isDownloading
        self.percentDownloaded = percentDownloaded
        self.errorDescription = errorDescription
        self.isUploaded = isUploaded
        self.isUploading = isUploading
        self.percentUploaded = percentUploaded
        self.uploadErrorDescription = uploadErrorDescription
    }
}
