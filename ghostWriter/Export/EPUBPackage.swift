//
//  EPUBPackage.swift
//  ghostWriter
//
//  Builds the zip container an EPUB lives in.
//
//  WordPackage.create already zips a dictionary of entries, but it cannot be
//  reused here: it writes entries in sorted order and deflates all of them.
//  EPUB requires the `mimetype` entry to be written first and stored
//  uncompressed, because reading systems identify the file by reading those
//  exact bytes at a fixed offset in the archive. A deflated or out-of-order
//  mimetype produces a file that opens as a plain zip rather than a book.
//

import Foundation
import ZIPFoundation

nonisolated enum EPUBPackage {

    static func create(entries: [String: Data]) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(accessMode: .create)
        } catch {
            throw EPUBExportError.couldNotCreateDocument
        }

        // mimetype first, stored rather than deflated.
        if let mimetype = entries["mimetype"] {
            try add(
                path: "mimetype",
                data: mimetype,
                compression: .none,
                to: archive
            )
        }

        // Remaining entries in a stable order, so two exports of the same
        // document produce byte-identical packages.
        for path in entries.keys.sorted() where path != "mimetype" {
            guard let data = entries[path] else { continue }
            try add(path: path, data: data, compression: .deflate, to: archive)
        }

        guard let data = archive.data else {
            throw EPUBExportError.couldNotCreateDocument
        }
        return data
    }

    private static func add(
        path: String,
        data: Data,
        compression: CompressionMethod,
        to archive: Archive
    ) throws {
        do {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: compression,
                provider: { position, size in
                    let start = Int(position)
                    return data.subdata(in: start..<(start + size))
                }
            )
        } catch {
            throw EPUBExportError.couldNotCreateDocument
        }
    }
}

nonisolated enum EPUBExportError: LocalizedError, Equatable, Sendable {
    case couldNotCreateDocument

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDocument:
            return "The EPUB could not be created."
        }
    }
}
