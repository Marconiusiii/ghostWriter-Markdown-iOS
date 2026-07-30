//
//  ICloudDocumentMonitor.swift
//  ghostWriter
//
//  Watches the app's public iCloud Documents container. NSMetadataQuery is
//  required here because it can report files that exist in iCloud before their
//  contents have been downloaded to this device.
//

import Foundation
import Observation

@Observable
final class ICloudDocumentMonitor: NSObject {
    private(set) var snapshots: [ICloudDocumentSnapshot] = []
    private(set) var revision = 0

    @ObservationIgnored private let query = NSMetadataQuery()
    @ObservationIgnored private var rootDirectory: URL?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false

    override init() {
        super.init()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(value: true)
        query.notificationBatchingInterval = 0.2
    }

    func start(rootDirectory: URL) {
        let standardizedRoot = rootDirectory.standardizedFileURL
        if self.rootDirectory == standardizedRoot, query.isStarted {
            return
        }

        stop()
        self.rootDirectory = standardizedRoot
        snapshots = []
        revision += 1

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataChanged),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataChanged),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        isObserving = true
        _ = query.start()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        if query.isStarted {
            query.stop()
        }
        if isObserving {
            NotificationCenter.default.removeObserver(
                self,
                name: .NSMetadataQueryDidFinishGathering,
                object: query
            )
            NotificationCenter.default.removeObserver(
                self,
                name: .NSMetadataQueryDidUpdate,
                object: query
            )
            isObserving = false
        }
        rootDirectory = nil
    }

    @objc private func metadataChanged() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.publishCurrentResults()
        }
    }

    private func publishCurrentResults() {
        guard let rootDirectory else { return }

        query.disableUpdates()
        let records = query.results.compactMap { result in
            Self.record(from: result)
        }
        query.enableUpdates()

        snapshots = Self.snapshots(
            from: records,
            rootDirectory: rootDirectory
        )
        revision += 1
    }

    nonisolated static func snapshots(
        from records: [ICloudMetadataRecord],
        rootDirectory: URL
    ) -> [ICloudDocumentSnapshot] {
        let root = rootDirectory.standardizedFileURL

        return records.compactMap { record in
            let url = record.url.standardizedFileURL
            guard Document.isMarkdown(url),
                  let relativeComponents = relativePathComponents(
                    for: url,
                    under: root
                  ) else {
                return nil
            }

            let isRecentlyDeleted: Bool
            if relativeComponents.count == 1 {
                isRecentlyDeleted = false
            } else if relativeComponents.count == 2,
                      relativeComponents[0] == "Recently Deleted" {
                isRecentlyDeleted = true
            } else {
                return nil
            }

            return ICloudDocumentSnapshot(
                url: url,
                created: record.created ?? .distantPast,
                modified: record.modified ?? record.created ?? .distantPast,
                byteCount: record.byteCount ?? 0,
                availability: DocumentAvailability.iCloudState(
                    downloadingStatus: record.downloadingStatus,
                    isDownloading: record.isDownloading,
                    percentDownloaded: record.percentDownloaded,
                    errorDescription: record.errorDescription
                ),
                isRecentlyDeleted: isRecentlyDeleted
            )
        }
    }

    private nonisolated static func relativePathComponents(
        for url: URL,
        under root: URL
    ) -> [String]? {
        let rootComponents = root.pathComponents
        let urlComponents = url.pathComponents
        guard urlComponents.starts(with: rootComponents),
              urlComponents.count > rootComponents.count else {
            return nil
        }
        return Array(urlComponents.dropFirst(rootComponents.count))
    }

    private nonisolated static func record(
        from result: Any
    ) -> ICloudMetadataRecord? {
        guard let item = result as? NSMetadataItem,
              let url = item.value(
                forAttribute: NSMetadataItemURLKey
              ) as? URL else {
            return nil
        }

        return ICloudMetadataRecord(
            url: url,
            created: item.value(
                forAttribute: NSMetadataItemFSCreationDateKey
            ) as? Date,
            modified: item.value(
                forAttribute: NSMetadataItemFSContentChangeDateKey
            ) as? Date,
            byteCount: (
                item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber
            )?.intValue,
            downloadingStatus: item.value(
                forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
            ) as? String,
            isDownloading: (
                item.value(
                    forAttribute: NSMetadataUbiquitousItemIsDownloadingKey
                ) as? NSNumber
            )?.boolValue ?? false,
            percentDownloaded: (
                item.value(
                    forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey
                ) as? NSNumber
            )?.doubleValue,
            errorDescription: (
                item.value(
                    forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey
                ) as? NSError
            )?.localizedDescription
        )
    }
}
