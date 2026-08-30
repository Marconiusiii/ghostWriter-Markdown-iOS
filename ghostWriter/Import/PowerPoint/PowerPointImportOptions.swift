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

nonisolated enum PowerPointImportError: LocalizedError, Equatable {
    case invalidPackage
    case encrypted
    case limitExceeded(PowerPointImportLimit)
    case invalidXML
    case noSlides

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            return String(localized: "The selected file is not a valid PowerPoint presentation.")
        case .encrypted:
            return String(localized: "Password-protected PowerPoint presentations cannot be imported.")
        case .limitExceeded(let limit):
            return limit.description
        case .invalidXML:
            return String(localized: "The PowerPoint presentation contains unreadable or unsafe content.")
        case .noSlides:
            return String(localized: "No slides match the selected import options.")
        }
    }
}

nonisolated enum PowerPointImportLimit: Equatable, Sendable {
    case fileSize, packageEntries, slides, documentPart, documentContent
    case imageSize, imageContent, imageCount, imageDimensions
    case xmlElements, xmlDepth, xmlText

    var description: String {
        switch self {
        case .fileSize:
            return String(localized: "The presentation exceeds the 512 MiB file-size limit.")
        case .packageEntries:
            return String(localized: "The presentation exceeds the limit of 4,096 internal files and folders.")
        case .slides:
            return String(localized: "The presentation exceeds the limit of 500 slides, including hidden slides.")
        case .documentPart:
            return String(localized: "An internal document part exceeds the 8 MiB limit.")
        case .documentContent:
            return String(localized: "The unpacked document content exceeds the 96 MiB limit, excluding images.")
        case .imageSize:
            return String(localized: "An image exceeds the 10 MiB limit.")
        case .imageContent:
            return String(localized: "The unpacked images exceed the separate 96 MiB image limit.")
        case .imageCount:
            return String(localized: "The presentation exceeds the import limit of 128 unique images.")
        case .imageDimensions:
            return String(localized: "An image exceeds the limit of 40 million pixels.")
        case .xmlElements:
            return String(localized: "An internal XML part exceeds the limit of 150,000 elements.")
        case .xmlDepth:
            return String(localized: "An internal XML part exceeds the limit of 64 nested elements.")
        case .xmlText:
            return String(localized: "The text in an internal XML part exceeds the 8 MiB limit.")
        }
    }
}
