//
//  DocumentStatus.swift
//  ghostWriter
//
//  Produces the editor's optional status-bar text from the document and its
//  current selection. This is presentation-independent so it can be tested
//  without VoiceOver, UIKit, or a live editor.
//

import Foundation

struct DocumentStatusOptions: Equatable {
    var lineAndColumn = true
    var lineCount = true
    var wordCount = true
    var characterCount = true
    var headingLevel = false
    var selectedWordCount = false
    var selectedCharacterCount = false
}

struct DocumentStatus: Equatable {
    let currentLine: Int
    let currentColumn: Int
    let lineCount: Int
    let wordCount: Int
    let characterCount: Int
    let headingLevel: Int?
    let selectedWordCount: Int
    let selectedCharacterCount: Int

    static func calculate(text: String, selection: TextSelection) -> DocumentStatus {
        let safeLocation = min(max(0, selection.location), text.count)
        let safeLength = min(max(0, selection.length), text.count - safeLocation)
        let caretIndex = text.index(text.startIndex, offsetBy: safeLocation)
        let prefix = text[..<caretIndex]

        let currentLine = prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        let currentColumn = prefix.reversed().prefix { $0 != "\n" }.count + 1

        let lines = text.components(separatedBy: "\n")
        let lineIndex = min(currentLine - 1, max(0, lines.count - 1))
        let line = lines[lineIndex]
        let structure = LineAnalyzer.analyze(
            line,
            insideCodeBlock: LineAnalyzer.isInsideCodeBlock(
                lines: lines,
                lineIndex: lineIndex
            )
        )

        let selectedStart = caretIndex
        let selectedEnd = text.index(selectedStart, offsetBy: safeLength)
        let selectedText = String(text[selectedStart..<selectedEnd])

        let headingLevel: Int?
        if case .heading(let level) = structure.kind {
            headingLevel = level
        } else {
            headingLevel = nil
        }

        return DocumentStatus(
            currentLine: currentLine,
            currentColumn: currentColumn,
            lineCount: lines.count,
            wordCount: countWords(in: text),
            characterCount: text.count,
            headingLevel: headingLevel,
            selectedWordCount: countWords(in: selectedText),
            selectedCharacterCount: selectedText.count
        )
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

    private static func countWords(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func countDescription(_ count: Int, singular: String, plural: String) -> String {
        "\(count.formatted()) \(count == 1 ? singular : plural)"
    }
}
