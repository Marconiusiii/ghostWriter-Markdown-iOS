//
//  ICloudDocumentMonitorTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct ICloudDocumentMonitorTests {
    @Test func snapshotIncludesLibraryAndRecentlyDeletedDocuments() {
        let root = URL(fileURLWithPath: "/iCloud/Documents", isDirectory: true)
        let records = [
            record(
                at: root.appendingPathComponent("Draft.md"),
                status: URLUbiquitousItemDownloadingStatus.current.rawValue
            ),
            record(
                at: root
                    .appendingPathComponent("Recently Deleted")
                    .appendingPathComponent("Old.md"),
                status:
                    URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue
            )
        ]

        let snapshots = ICloudDocumentMonitor.snapshots(
            from: records,
            rootDirectory: root
        )

        #expect(snapshots.count == 2)
        #expect(
            snapshots.first { $0.url.lastPathComponent == "Draft.md" }?
                .isRecentlyDeleted == false
        )
        #expect(
            snapshots.first { $0.url.lastPathComponent == "Old.md" }?
                .isRecentlyDeleted == true
        )
    }

    @Test func snapshotIncludesNestedFoldersAndIgnoresUnsupportedFiles() {
        let root = URL(fileURLWithPath: "/iCloud/Documents", isDirectory: true)
        let records = [
            record(
                at: root
                    .appendingPathComponent("Another Folder")
                    .appendingPathComponent("Nested.md"),
                status: URLUbiquitousItemDownloadingStatus.current.rawValue
            ),
            record(
                at: root.appendingPathComponent("Photo.jpg"),
                status: URLUbiquitousItemDownloadingStatus.current.rawValue
            ),
            record(
                at: URL(fileURLWithPath: "/Other/Documents/Outside.md"),
                status: URLUbiquitousItemDownloadingStatus.current.rawValue
            )
        ]

        let snapshots = ICloudDocumentMonitor.snapshots(
            from: records,
            rootDirectory: root
        )
        #expect(snapshots.count == 1)
        #expect(snapshots[0].url.lastPathComponent == "Nested.md")
    }

    @Test func snapshotPreservesRemoteMetadataAndState() {
        let root = URL(fileURLWithPath: "/iCloud/Documents", isDirectory: true)
        let created = Date(timeIntervalSince1970: 100)
        let modified = Date(timeIntervalSince1970: 200)
        let metadata = ICloudMetadataRecord(
            url: root.appendingPathComponent("Remote.markdown"),
            created: created,
            modified: modified,
            byteCount: 321,
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil
        )

        let snapshot = ICloudDocumentMonitor.snapshots(
            from: [metadata],
            rootDirectory: root
        ).first

        #expect(snapshot?.created == created)
        #expect(snapshot?.modified == modified)
        #expect(snapshot?.byteCount == 321)
        #expect(snapshot?.availability == .waitingForICloud)
    }

    @Test func missingDownloadStatusDoesNotAddAVisibleFileStatus() {
        let root = URL(fileURLWithPath: "/iCloud/Documents", isDirectory: true)
        let metadata = ICloudMetadataRecord(
            url: root.appendingPathComponent("Local.md"),
            created: Date(timeIntervalSince1970: 100),
            modified: Date(timeIntervalSince1970: 200),
            byteCount: 12,
            downloadingStatus: nil,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil
        )

        let snapshot = ICloudDocumentMonitor.snapshots(
            from: [metadata],
            rootDirectory: root
        ).first

        #expect(snapshot?.availability == .available)
        #expect(snapshot?.availability.statusDescription == nil)
    }

    @Test func snapshotIncludesUploadProgress() {
        let root = URL(fileURLWithPath: "/iCloud/Documents", isDirectory: true)
        let metadata = ICloudMetadataRecord(
            url: root.appendingPathComponent("Uploading.md"),
            created: Date(timeIntervalSince1970: 100),
            modified: Date(timeIntervalSince1970: 200),
            byteCount: 12,
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.current.rawValue,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil,
            isUploaded: false,
            isUploading: true,
            percentUploaded: 31.7
        )

        let snapshot = ICloudDocumentMonitor.snapshots(
            from: [metadata],
            rootDirectory: root
        ).first

        #expect(snapshot?.availability == .uploading(percent: 32))
        #expect(snapshot?.availability.isAvailable == true)
    }

    @Test func snapshotIncludesUploadFailure() {
        let root = URL(fileURLWithPath: "/iCloud/Documents", isDirectory: true)
        let metadata = ICloudMetadataRecord(
            url: root.appendingPathComponent("Failed.md"),
            created: Date(timeIntervalSince1970: 100),
            modified: Date(timeIntervalSince1970: 200),
            byteCount: 12,
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.current.rawValue,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil,
            isUploaded: false,
            uploadErrorDescription: "Account unavailable"
        )

        let snapshot = ICloudDocumentMonitor.snapshots(
            from: [metadata],
            rootDirectory: root
        ).first

        #expect(
            snapshot?.availability
                == .uploadFailed("Account unavailable")
        )
    }

    private func record(
        at url: URL,
        status: String
    ) -> ICloudMetadataRecord {
        ICloudMetadataRecord(
            url: url,
            created: Date(timeIntervalSince1970: 100),
            modified: Date(timeIntervalSince1970: 200),
            byteCount: 12,
            downloadingStatus: status,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil
        )
    }
}
