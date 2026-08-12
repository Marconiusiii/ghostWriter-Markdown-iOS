//
//  DocumentStatus.swift
//  ghostWriter
//
//  Produces the editor's optional status-bar text from the document and its
//  current selection. This is presentation-independent so it can be tested
//  without VoiceOver, UIKit, or a live editor.
//

import Foundation

nonisolated struct DocumentStatusOptions: Equatable, Sendable {
    var lineAndColumn = true
    var lineCount = true
    var wordCount = true
    var characterCount = true
    var headingLevel = false
    var selectedWordCount = false
    var selectedCharacterCount = false
}

/// Document-wide information that changes only when the text changes. Keeping
/// line boundaries and counts here means moving through a long document does
/// not repeatedly rescan every character just to update the current position.
nonisolated struct DocumentStatusIndex: Sendable {
    let sourceText: String
    private let lineStartOffsets: [Int]
    private let headingLevels: [Int?]

    let lineCount: Int
    let wordCount: Int
    let characterCount: Int

    init(text: String) {
        self.sourceText = text
        let lines = text.components(separatedBy: "\n")
        self.lineCount = lines.count
        self.wordCount = Self.countWords(in: text)
        self.characterCount = text.count

        var starts: [Int] = []
        var headings: [Int?] = []
        var nextStart = 0
        var insideCodeBlock = false

        for line in lines {
            starts.append(nextStart)
            let structure = LineAnalyzer.analyze(
                line,
                insideCodeBlock: insideCodeBlock
            )

            if case .heading(let level) = structure.kind {
                headings.append(level)
            } else {
                headings.append(nil)
            }

            if case .codeFence = structure.kind {
                insideCodeBlock.toggle()
            }
            nextStart += line.count + 1
        }

        self.lineStartOffsets = starts
        self.headingLevels = headings
    }

    func status(selection: TextSelection) -> DocumentStatus {
        let safeLocation = min(max(0, selection.location), characterCount)
        let safeLength = min(max(0, selection.length), characterCount - safeLocation)
        let lineIndex = lineIndex(containing: safeLocation)
        let selectedText: String

        if safeLength > 0 {
            let selectedStart = sourceText.index(
                sourceText.startIndex,
                offsetBy: safeLocation
            )
            let selectedEnd = sourceText.index(
                selectedStart,
                offsetBy: safeLength
            )
            selectedText = String(sourceText[selectedStart..<selectedEnd])
        } else {
            selectedText = ""
        }

        return DocumentStatus(
            currentLine: lineIndex + 1,
            currentColumn: safeLocation - lineStartOffsets[lineIndex] + 1,
            lineCount: lineCount,
            wordCount: wordCount,
            characterCount: characterCount,
            headingLevel: headingLevels[lineIndex],
            selectedWordCount: Self.countWords(in: selectedText),
            selectedCharacterCount: safeLength
        )
    }

    private func lineIndex(containing characterOffset: Int) -> Int {
        var lowerBound = 0
        var upperBound = lineStartOffsets.count

        while lowerBound + 1 < upperBound {
            let candidate = (lowerBound + upperBound) / 2
            if lineStartOffsets[candidate] <= characterOffset {
                lowerBound = candidate
            } else {
                upperBound = candidate
            }
        }

        return lowerBound
    }

    private static func countWords(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

nonisolated struct DocumentStatus: Equatable, Sendable {
    let currentLine: Int
    let currentColumn: Int
    let lineCount: Int
    let wordCount: Int
    let characterCount: Int
    let headingLevel: Int?
    let selectedWordCount: Int
    let selectedCharacterCount: Int

    static func calculate(text: String, selection: TextSelection) -> DocumentStatus {
        DocumentStatusIndex(text: text).status(selection: selection)
    }

    func description(options: DocumentStatusOptions) -> String {
        var parts: [String] = []

        if options.lineAndColumn {
            parts.append("Line \(currentLine)")
            parts.append("Column \(currentColumn)")
        }
        if options.lineCount {
            parts.append(countDescription(lineCount, singular: "line", plural: "lines"))
        }
        if options.wordCount {
            parts.append(countDescription(wordCount, singular: "word", plural: "words"))
        }
        if options.characterCount {
            parts.append(countDescription(characterCount, singular: "character", plural: "characters"))
        }
        if options.headingLevel, let headingLevel {
            parts.append("Heading level \(headingLevel)")
        }
        if selectedCharacterCount > 0 {
            if options.selectedWordCount {
                parts.append(
                    countDescription(
                        selectedWordCount,
                        singular: "selected word",
                        plural: "selected words"
                    )
                )
            }
            if options.selectedCharacterCount {
                parts.append(
                    countDescription(
                        selectedCharacterCount,
                        singular: "selected character",
                        plural: "selected characters"
                    )
                )
            }
        }

        return parts.isEmpty ? "No status information selected" : parts.joined(separator: ", ")
    }

    private func countDescription(_ count: Int, singular: String, plural: String) -> String {
        "\(count.formatted()) \(count == 1 ? singular : plural)"
    }
}
