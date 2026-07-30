//
//  DocumentAvailabilityTests.swift
//  ghostWriterTests
//

import Foundation
import Testing
@testable import ghostWriter

struct DocumentAvailabilityTests {
    @Test func currentICloudDocumentIsAvailable() {
        let state = DocumentAvailability.iCloudState(
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.current.rawValue,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil
        )

        #expect(state == .available)
        #expect(state.statusDescription == nil)
    }

    @Test func remoteDocumentWaitsForICloud() {
        let state = DocumentAvailability.iCloudState(
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil
        )

        #expect(state == .waitingForICloud)
        #expect(state.statusDescription == "Waiting for iCloud")
    }

    @Test func missingMetadataIsCheckingRatherThanWaiting() {
        let state = DocumentAvailability.iCloudState(
            downloadingStatus: nil,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil
        )

        #expect(state == .checkingICloud)
        #expect(state.statusDescription == "Checking iCloud")
    }

    @Test func downloadProgressIsClampedAndRounded() {
        let state = DocumentAvailability.iCloudState(
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue,
            isDownloading: true,
            percentDownloaded: 47.6,
            errorDescription: nil
        )

        #expect(state == .downloading(percent: 48))
        #expect(state.statusDescription == "Downloading, 48 percent")
    }

    @Test func downloadedButNotCurrentDocumentIsUpdating() {
        let state = DocumentAvailability.iCloudState(
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.downloaded.rawValue,
            isDownloading: false,
            percentDownloaded: nil,
            errorDescription: nil
        )

        #expect(state == .updating)
        #expect(state.statusDescription == "Updating from iCloud")
    }

    @Test func downloadErrorTakesPriority() {
        let state = DocumentAvailability.iCloudState(
            downloadingStatus:
                URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue,
            isDownloading: true,
            percentDownloaded: 20,
            errorDescription: "No network connection"
        )

        #expect(state == .failed("No network connection"))
        #expect(state.statusDescription == "Download failed")
    }
}
