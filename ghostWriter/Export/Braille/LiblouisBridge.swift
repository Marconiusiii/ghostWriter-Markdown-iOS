//
//  LiblouisBridge.swift
//  ghostWriter
//
//  Swift's side of the liblouis C library.
//
//  All of the unsafe work is deliberately confined here — pointer buffers,
//  manual length juggling, and the C library's global state — so that the rest
//  of the braille export is ordinary Swift. Three things about liblouis shape
//  this file, and each is easy to get wrong in a way that still looks like it
//  worked:
//
//  1. It emits ASCII braille by default, the old BRF convention where a cell is
//     a printable ASCII character. eBraille requires real Unicode braille
//     patterns, which need an explicit mode flag.
//  2. Tables are found through the LOUIS_TABLEPATH environment variable.
//     lou_setDataPath, the function the documentation leads with, is deprecated
//     as of 3.38 and does not reliably work.
//  3. Translation is not safe to call concurrently. The library keeps a global
//     compiled-table cache with no locking of its own.
//

import Foundation
import CLiblouis

/// Translates text with liblouis.
///
/// An actor rather than a namespace: liblouis keeps global mutable state in its
/// table cache, so concurrent translations would race. Serialising here means
/// callers never have to think about it.
actor LiblouisBridge: BrailleTranslator {

    static let shared = LiblouisBridge()

    /// Unicode braille output. `dotsIO` makes liblouis work in dot patterns
    /// rather than characters, and `ucBrl` renders those patterns as U+2800
    /// block characters. Without both, the output is ASCII braille that would
    /// pass casual inspection and fail eBraille conformance.
    private static let unicodeBrailleMode = Int32(dotsIO.rawValue | ucBrl.rawValue)

    private var tablePathConfigured = false

    /// Points liblouis at the tables bundled with the app.
    ///
    /// Done once, lazily, rather than at launch: an app that never exports
    /// braille should not pay for it, and setting an environment variable from
    /// an actor keeps it off the main thread.
    private func configureTablePathIfNeeded() throws {
        guard !tablePathConfigured else { return }

        guard let tables = Bundle.main.url(forResource: "tables", withExtension: nil)?.path
                ?? Bundle.main.resourceURL?.appendingPathComponent("tables").path,
              FileManager.default.fileExists(atPath: tables) else {
            throw BrailleTranslationError.tablesMissing
        }

        setenv("LOUIS_TABLEPATH", tables, 1)
        tablePathConfigured = true
    }

    func translate(_ translation: BrailleTranslationInput, grade: BrailleGrade) throws -> String {
        let text = translation.text
        guard !text.isEmpty else { return "" }
        try configureTablePathIfNeeded()

        // liblouis speaks UTF-16 — widechar is a 16-bit unsigned short in this
        // build — which is Swift's own string representation, so this hands the
        // characters over without converting between encodings.
        var input = Array(text.utf16)
        var inputLength = Int32(input.count)
        guard translation.typeforms.isEmpty || translation.typeforms.count == input.count else {
            throw BrailleTranslationError.invalidTypeforms
        }

        // Braille is not always shorter than print. Grade 1 in particular grows:
        // every capital letter and every number gains an indicator cell, so a
        // string of digits can more than double. Starting at four times the
        // input covers realistic text, and the retry loop covers the rest.
        var capacity = max(input.count * 4, 128)

        for _ in 0..<4 {
            // liblouis may place a trailing wide-character terminator after
            // the reported output. Keep one extra element outside the length
            // passed to C so a full buffer cannot write past Swift's storage.
            var output = [UInt16](repeating: 0, count: capacity + 1)
            var outputLength = Int32(capacity)
            inputLength = Int32(input.count)
            var typeforms = translation.typeforms.isEmpty
                ? nil
                : translation.typeforms.map { formtype($0.rawValue) }

            let result = grade.tableName.withCString { table in
                input.withUnsafeMutableBufferPointer { inputBuffer in
                    output.withUnsafeMutableBufferPointer { outputBuffer in
                        if typeforms == nil {
                            return lou_translateString(
                                table,
                                inputBuffer.baseAddress,
                                &inputLength,
                                outputBuffer.baseAddress,
                                &outputLength,
                                nil,
                                nil,
                                Self.unicodeBrailleMode
                            )
                        }
                        return typeforms!.withUnsafeMutableBufferPointer { forms in
                            lou_translateString(
                                table,
                                inputBuffer.baseAddress,
                                &inputLength,
                                outputBuffer.baseAddress,
                                &outputLength,
                                forms.baseAddress,
                                nil,
                                Self.unicodeBrailleMode
                            )
                        }
                    }
                }
            }

            guard result != 0 else {
                throw BrailleTranslationError.translationFailed(grade: grade)
            }

            guard outputLength >= 0, outputLength <= Int32(capacity) else {
                throw BrailleTranslationError.translationFailed(grade: grade)
            }

            // liblouis reports how much of the input it consumed. A short read
            // means the output buffer filled up, so the translation is a
            // truncated fragment rather than a failure it reports as one.
            if inputLength < Int32(input.count) {
                capacity *= 4
                continue
            }

            let translated = String(
                decoding: output.prefix(Int(outputLength)),
                as: UTF16.self
            )
            guard translated.unicodeScalars.allSatisfy({ scalar in
                (0x2800...0x283F).contains(scalar.value)
                    || scalar.value == 0x20
                    || scalar.value == 0x0A
                    || scalar.value == 0x0D
                    || scalar.value == 0x09
            }) else {
                throw BrailleTranslationError.invalidOutput
            }
            return translated
        }

        throw BrailleTranslationError.translationFailed(grade: grade)
    }
}

nonisolated enum BrailleTranslationError: LocalizedError, Equatable, Sendable {
    case tablesMissing
    case invalidTypeforms
    case invalidOutput
    case translationFailed(grade: BrailleGrade)

    var errorDescription: String? {
        switch self {
        case .tablesMissing:
            return String(localized: "The braille translation tables could not be found.")
        case .invalidTypeforms:
            return String(localized: "The braille emphasis information did not match the text.")
        case .invalidOutput:
            return String(localized: "The braille translator produced characters that are not valid six-dot braille.")
        case .translationFailed(let grade):
            return String(localized: "The document could not be translated into \(grade.systemName).")
        }
    }
}
