//
//  PowerPointPackage.swift
//  ghostWriter
//
//  Creates the ZIP container used by PresentationML.
//

import Foundation
import ZIPFoundation

nonisolated enum PowerPointPackage {
    static func create(entries: [String: Data]) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(accessMode: .create)
        } catch {
            throw PowerPointExportError.couldNotCreateDocument
        }

        do {
            for path in entries.keys.sorted() {
                guard let data = entries[path] else { continue }
                try archive.addEntry(
                    with: path,
                    type: .file,
                    uncompressedSize: Int64(data.count),
                    compressionMethod: .deflate,
                    provider: { position, size in
                        let start = Int(position)
                        return data.subdata(in: start..<(start + size))
                    }
                )
            }
        } catch {
            throw PowerPointExportError.couldNotCreateDocument
        }

        guard let data = archive.data else {
            throw PowerPointExportError.couldNotCreateDocument
        }
        return data
    }
}
