//
//  LineNavigation.swift
//  ghostWriter
//
//  Validates a human-readable, one-based line number and converts it into the
//  Character offset used by the editor, Outline, and Status Bar.
//

import Foundation

enum LineNavigationError: Error, Equatable {
    case invalidEntry(lineCount: Int)
    case lineDoesNotExist(requested: Int, lineCount: Int)

    var title: String {
        switch self {
        case .invalidEntry:
            return "Enter a Line Number"
        case .lineDoesNotExist:
            return "Line Does Not Exist"
        }
    }

    var message: String {
        switch self {
        case .invalidEntry(let lineCount):
            return "Enter a whole number from 1 through \(lineCount)."
        case .lineDoesNotExist(let requested, let lineCount):
            return "Line \(requested) does not exist. This document has \(lineCount) \(lineCount == 1 ? "line" : "lines")."
        }
    }
}

struct LineNavigation {
    static func destination(
        for input: String,
        in text: String
    ) -> Result<Int, LineNavigationError> {
        let starts = lineStartOffsets(in: text)
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let requested = Int(trimmed), requested > 0 else {
            return .failure(.invalidEntry(lineCount: starts.count))
        }

        guard requested <= starts.count else {
            return .failure(
                .lineDoesNotExist(requested: requested, lineCount: starts.count)
            )
        }

        return .success(starts[requested - 1])
    }

    static func lineCount(in text: String) -> Int {
        lineStartOffsets(in: text).count
    }

    private static func lineStartOffsets(in text: String) -> [Int] {
        var starts = [0]

        for (offset, character) in text.enumerated() where character.isNewline {
            starts.append(offset + 1)
        }

        return starts
    }
}
