import Foundation

/// Matches the editor's whitespace-delimited word and Swift Character counts.
nonisolated struct FolderTextCount: Equatable, Sendable {
    var words = 0
    var characters = 0

    static func count(_ text: String) throws -> Self {
        var result = Self()
        var insideWord = false
        for character in text {
            if result.characters % 4096 == 0 { try Task.checkCancellation() }
            result.characters += 1
            if character.isWhitespace { insideWord = false }
            else if !insideWord { result.words += 1; insideWord = true }
        }
        return result
    }
}
