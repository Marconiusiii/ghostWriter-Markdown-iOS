import Foundation

nonisolated struct PowerPointImportOptions: Codable, Equatable, Sendable {
    var slideText = true
    var tables = true
    var images = true
    var speakerNotes = true
    var textFormatting = true
    var links = true
    var hiddenSlides = false
    var decorativeImages = false
    var slideNumbers = false
    var dates = false
    var footers = false
}

nonisolated enum PowerPointImportError: LocalizedError {
    case invalidPackage
    case encrypted
    case oversized
    case invalidXML
    case noSlides

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            return String(localized: "The selected file is not a valid PowerPoint presentation.")
        case .encrypted:
            return String(localized: "Password-protected PowerPoint presentations cannot be imported.")
        case .oversized:
            return String(localized: "The PowerPoint presentation is too large or complex to import safely.")
        case .invalidXML:
            return String(localized: "The PowerPoint presentation contains unreadable or unsafe content.")
        case .noSlides:
            return String(localized: "No slides match the selected import options.")
        }
    }
}
