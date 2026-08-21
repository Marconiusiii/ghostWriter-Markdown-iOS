//
//  AppSettings.swift
//  ghostWriter
//
//  User preferences, persisted in UserDefaults. Kept in one observable object
//  so any view can read a setting without threading it through initialisers.
//

import Foundation
import Observation
import SwiftUI

/// How a tab keypress and the indent controls change indentation. Mirrors the
/// indentation options from the web app.
enum IndentUnit: String, CaseIterable, Identifiable {
    case tab
    case twoSpaces
    case fourSpaces

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tab: return String(localized: "Tabs")
        case .twoSpaces: return String(localized: "2 Spaces")
        case .fourSpaces: return String(localized: "4 Spaces")
        }
    }

    /// The literal text inserted for one level of indentation.
    var string: String {
        switch self {
        case .tab: return "\t"
        case .twoSpaces: return "  "
        case .fourSpaces: return "    "
        }
    }
}

/// Appearance override. Defaults to following the system, which is what most
/// users want; the explicit options exist for people who need one specific
/// contrast regardless of the system setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "Follow System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The typeface used only for raw markdown editing. Every option starts with
/// the preferred body text style, so choosing a design never opts out of
/// Dynamic Type or its accessibility sizes.
enum EditorFontDesign: String, CaseIterable, Identifiable {
    case monospaced
    case system
    case rounded
    case serif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monospaced: return String(localized: "Monospaced")
        case .system: return String(localized: "System")
        case .rounded: return String(localized: "Rounded")
        case .serif: return String(localized: "Serif")
        }
    }
}

enum VoiceOverVerbosity: String, CaseIterable, Identifiable {
    case off
    case light
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return String(localized: "Off")
        case .light: return String(localized: "Light")
        case .full: return String(localized: "Full")
        }
    }

    var description: String {
        switch self {
        case .off:
            return String(localized: "No Markdown editing announcements.")
        case .light:
            return String(localized: "Announces list changes, indentation levels, and Insert actions.")
        case .full:
            return String(localized: "Announces Light feedback and completed Markdown structures as you type.")
        }
    }

    var includesLightFeedback: Bool { self != .off }
    var includesTypedStructureFeedback: Bool { self == .full }
}

@Observable
final class AppSettings {
    var appLaunchBehavior: AppLaunchBehavior {
        didSet {
            defaults.set(
                appLaunchBehavior.rawValue,
                forKey: Keys.appLaunchBehavior
            )
        }
    }

    var newDocumentCreationMode: NewDocumentCreationMode {
        didSet {
            defaults.set(
                newDocumentCreationMode.rawValue,
                forKey: Keys.newDocumentCreationMode
            )
        }
    }

    var indentUnit: IndentUnit {
        didSet { defaults.set(indentUnit.rawValue, forKey: Keys.indentUnit) }
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var editorFontDesign: EditorFontDesign {
        didSet { defaults.set(editorFontDesign.rawValue, forKey: Keys.editorFontDesign) }
    }

    /// Shows one concise, configurable document-status element immediately
    /// after the editor. It is off by default so existing editing sessions do
    /// not gain another focus stop until the writer asks for it.
    var statusBarEnabled: Bool {
        didSet { defaults.set(statusBarEnabled, forKey: Keys.statusBarEnabled) }
    }

    var statusShowsLineAndColumn: Bool {
        didSet { defaults.set(statusShowsLineAndColumn, forKey: Keys.statusLineAndColumn) }
    }

    var statusShowsLineCount: Bool {
        didSet { defaults.set(statusShowsLineCount, forKey: Keys.statusLineCount) }
    }

    var statusShowsWordCount: Bool {
        didSet { defaults.set(statusShowsWordCount, forKey: Keys.statusWordCount) }
    }

    var statusShowsCharacterCount: Bool {
        didSet { defaults.set(statusShowsCharacterCount, forKey: Keys.statusCharacterCount) }
    }

    var statusShowsHeadingLevel: Bool {
        didSet { defaults.set(statusShowsHeadingLevel, forKey: Keys.statusHeadingLevel) }
    }

    var statusShowsSelectedWordCount: Bool {
        didSet { defaults.set(statusShowsSelectedWordCount, forKey: Keys.statusSelectedWordCount) }
    }

    // MARK: - eBraille export

    var eBrailleCreator: String {
        didSet { defaults.set(eBrailleCreator, forKey: Keys.eBrailleCreator) }
    }

    var eBrailleTranscriber: String {
        didSet { defaults.set(eBrailleTranscriber, forKey: Keys.eBrailleTranscriber) }
    }

    var eBrailleGrade: BrailleGrade {
        didSet { defaults.set(eBrailleGrade.rawValue, forKey: Keys.eBrailleGrade) }
    }

    var eBrailleCopyrightDate: String {
        didSet { defaults.set(eBrailleCopyrightDate, forKey: Keys.eBrailleCopyrightDate) }
    }

    var eBrailleIsCompleteDocument: Bool {
        didSet {
            defaults.set(
                eBrailleIsCompleteDocument,
                forKey: Keys.eBrailleIsCompleteDocument
            )
        }
    }

    var eBrailleSource: String {
        didSet { defaults.set(eBrailleSource, forKey: Keys.eBrailleSource) }
    }

    var eBraillePublisher: String {
        didSet { defaults.set(eBraillePublisher, forKey: Keys.eBraillePublisher) }
    }

    var eBrailleRights: String {
        didSet { defaults.set(eBrailleRights, forKey: Keys.eBrailleRights) }
    }

    var eBrailleSubject: String {
        didSet { defaults.set(eBrailleSubject, forKey: Keys.eBrailleSubject) }
    }

    var eBrailleDescription: String {
        didSet { defaults.set(eBrailleDescription, forKey: Keys.eBrailleDescription) }
    }

    var eBrailleEducationLevel: String {
        didSet {
            defaults.set(
                eBrailleEducationLevel,
                forKey: Keys.eBrailleEducationLevel
            )
        }
    }

    var eBrailleMetadataDefaults: EBrailleMetadata {
        EBrailleMetadata(
            creator: eBrailleCreator,
            transcriber: eBrailleTranscriber,
            grade: eBrailleGrade,
            copyrightYear: eBrailleCopyrightDate,
            isCompleteTranscription: eBrailleIsCompleteDocument,
            source: eBrailleSource,
            publisher: eBraillePublisher,
            rights: eBrailleRights,
            subject: eBrailleSubject,
            descriptionText: eBrailleDescription,
            educationLevel: eBrailleEducationLevel
        )
    }

    var brfCellsPerLine: Int {
        didSet { defaults.set(brfCellsPerLine, forKey: Keys.brfCellsPerLine) }
    }

    var brfLinesPerPage: Int {
        didSet { defaults.set(brfLinesPerPage, forKey: Keys.brfLinesPerPage) }
    }

    var statusShowsSelectedCharacterCount: Bool {
        didSet { defaults.set(statusShowsSelectedCharacterCount, forKey: Keys.statusSelectedCharacterCount) }
    }

    /// The theremin sound on render. On by default because it is part of the
    /// app's character, but it respects the silent switch and can be turned off.
    var renderSoundEnabled: Bool {
        didSet { defaults.set(renderSoundEnabled, forKey: Keys.renderSound) }
    }

    /// Automatic list continuation and numbering while typing.
    var smartListsEnabled: Bool {
        didSet { defaults.set(smartListsEnabled, forKey: Keys.smartLists) }
    }

    var keyboardShortcutsEnabled: Bool {
        didSet {
            defaults.set(
                keyboardShortcutsEnabled,
                forKey: Keys.keyboardShortcuts
            )
        }
    }

    var voiceOverVerbosity: VoiceOverVerbosity {
        didSet {
            defaults.set(
                voiceOverVerbosity.rawValue,
                forKey: Keys.voiceOverVerbosity
            )
        }
    }

    var headingSwipeNavigationEnabled: Bool {
        didSet {
            defaults.set(
                headingSwipeNavigationEnabled,
                forKey: Keys.headingSwipeNavigation
            )
        }
    }

    var sort: DocumentSort {
        didSet {
            defaults.set(sort.field.rawValue, forKey: Keys.sortField)
            defaults.set(sort.direction.rawValue, forKey: Keys.sortDirection)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // `object(forKey:)` distinguishes "never set" from "set to false", which
        // matters for the booleans that default to true.
        self.appLaunchBehavior = (
            defaults.string(forKey: Keys.appLaunchBehavior)
                .flatMap(AppLaunchBehavior.init(rawValue:))
        ) ?? .showLibrary
        self.newDocumentCreationMode = (
            defaults.string(forKey: Keys.newDocumentCreationMode)
                .flatMap(NewDocumentCreationMode.init(rawValue:))
        ) ?? .askForTitle
        self.indentUnit = (defaults.string(forKey: Keys.indentUnit)
            .flatMap(IndentUnit.init(rawValue:))) ?? .twoSpaces
        self.appearance = (defaults.string(forKey: Keys.appearance)
            .flatMap(AppearanceMode.init(rawValue:))) ?? .system
        self.editorFontDesign = (defaults.string(forKey: Keys.editorFontDesign)
            .flatMap(EditorFontDesign.init(rawValue:))) ?? .monospaced
        self.statusBarEnabled = defaults.object(forKey: Keys.statusBarEnabled) as? Bool ?? true
        self.statusShowsLineAndColumn = defaults.object(forKey: Keys.statusLineAndColumn) as? Bool ?? true
        self.statusShowsLineCount = defaults.object(forKey: Keys.statusLineCount) as? Bool ?? true
        self.statusShowsWordCount = defaults.object(forKey: Keys.statusWordCount) as? Bool ?? true
        self.statusShowsCharacterCount = defaults.object(forKey: Keys.statusCharacterCount) as? Bool ?? true
        self.statusShowsHeadingLevel = defaults.object(forKey: Keys.statusHeadingLevel) as? Bool ?? false
        self.statusShowsSelectedWordCount = defaults.object(forKey: Keys.statusSelectedWordCount) as? Bool ?? false
        self.statusShowsSelectedCharacterCount = defaults.object(forKey: Keys.statusSelectedCharacterCount) as? Bool ?? false
        self.eBrailleCreator = defaults.string(forKey: Keys.eBrailleCreator) ?? ""
        self.eBrailleTranscriber = defaults.string(forKey: Keys.eBrailleTranscriber) ?? ""
        // Grade 2 is what most braille readers prefer, so it is the default
        // rather than the less contracted grade 1.
        self.eBrailleGrade = (defaults.string(forKey: Keys.eBrailleGrade)
            .flatMap(BrailleGrade.init(rawValue:))) ?? .grade2
        self.eBrailleCopyrightDate = defaults.string(
            forKey: Keys.eBrailleCopyrightDate
        ) ?? ""
        self.eBrailleIsCompleteDocument = defaults.object(
            forKey: Keys.eBrailleIsCompleteDocument
        ) as? Bool ?? true
        self.eBrailleSource = defaults.string(forKey: Keys.eBrailleSource) ?? ""
        self.eBraillePublisher = defaults.string(forKey: Keys.eBraillePublisher) ?? ""
        self.eBrailleRights = defaults.string(forKey: Keys.eBrailleRights) ?? ""
        self.eBrailleSubject = defaults.string(forKey: Keys.eBrailleSubject) ?? ""
        self.eBrailleDescription = defaults.string(
            forKey: Keys.eBrailleDescription
        ) ?? ""
        self.eBrailleEducationLevel = defaults.string(
            forKey: Keys.eBrailleEducationLevel
        ) ?? ""
        // 40 by 25 is the standard braille page. Devices vary, so these are
        // remembered rather than fixed.
        let storedCells = defaults.integer(forKey: Keys.brfCellsPerLine)
        self.brfCellsPerLine = storedCells > 0 ? storedCells : 40
        let storedLines = defaults.integer(forKey: Keys.brfLinesPerPage)
        self.brfLinesPerPage = storedLines > 0 ? storedLines : 25
        self.renderSoundEnabled = defaults.object(forKey: Keys.renderSound) as? Bool ?? true
        self.smartListsEnabled = defaults.object(forKey: Keys.smartLists) as? Bool ?? true
        self.keyboardShortcutsEnabled =
            defaults.object(forKey: Keys.keyboardShortcuts) as? Bool ?? true
        self.voiceOverVerbosity = defaults.string(
            forKey: Keys.voiceOverVerbosity
        ).flatMap(VoiceOverVerbosity.init(rawValue:)) ?? .light
        self.headingSwipeNavigationEnabled =
            defaults.object(forKey: Keys.headingSwipeNavigation) as? Bool ?? true

        let field = (defaults.string(forKey: Keys.sortField)
            .flatMap(DocumentSortField.init(rawValue:))) ?? .modified
        let direction = (defaults.string(forKey: Keys.sortDirection)
            .flatMap(SortDirection.init(rawValue:))) ?? .descending
        self.sort = DocumentSort(field: field, direction: direction)
    }

    private enum Keys {
        static let appLaunchBehavior = "appLaunchBehavior"
        static let newDocumentCreationMode = "newDocumentCreationMode"
        static let indentUnit = "indentUnit"
        static let appearance = "appearance"
        static let editorFontDesign = "editorFontDesign"
        static let statusBarEnabled = "statusBarEnabled"
        static let statusLineAndColumn = "statusShowsLineAndColumn"
        static let statusLineCount = "statusShowsLineCount"
        static let statusWordCount = "statusShowsWordCount"
        static let statusCharacterCount = "statusShowsCharacterCount"
        static let statusHeadingLevel = "statusShowsHeadingLevel"
        static let statusSelectedWordCount = "statusShowsSelectedWordCount"
        static let statusSelectedCharacterCount = "statusShowsSelectedCharacterCount"
        static let eBrailleCreator = "eBrailleCreator"
        static let eBrailleTranscriber = "eBrailleTranscriber"
        static let eBrailleGrade = "eBrailleGrade"
        static let eBrailleCopyrightDate = "eBrailleCopyrightDate"
        static let eBrailleIsCompleteDocument = "eBrailleIsCompleteDocument"
        static let eBrailleSource = "eBrailleSource"
        static let eBraillePublisher = "eBraillePublisher"
        static let eBrailleRights = "eBrailleRights"
        static let eBrailleSubject = "eBrailleSubject"
        static let eBrailleDescription = "eBrailleDescription"
        static let eBrailleEducationLevel = "eBrailleEducationLevel"
        static let brfCellsPerLine = "brfCellsPerLine"
        static let brfLinesPerPage = "brfLinesPerPage"
        static let renderSound = "renderSoundEnabled"
        static let smartLists = "smartListsEnabled"
        static let keyboardShortcuts = "keyboardShortcutsEnabled"
        static let voiceOverVerbosity = "voiceOverVerbosity"
        static let headingSwipeNavigation = "headingSwipeNavigationEnabled"
        static let sortField = "sortField"
        static let sortDirection = "sortDirection"
    }
}
