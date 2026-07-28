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
        case .tab: return "Tabs"
        case .twoSpaces: return "2 Spaces"
        case .fourSpaces: return "4 Spaces"
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
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
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
        case .monospaced: return "Monospaced"
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        }
    }
}

@Observable
final class AppSettings {
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

    /// Announces the structure of the current line (heading level, list depth)
    /// as the editor's accessibility value.
    var announceLineStructure: Bool {
        didSet { defaults.set(announceLineStructure, forKey: Keys.announceStructure) }
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
        self.indentUnit = (defaults.string(forKey: Keys.indentUnit)
            .flatMap(IndentUnit.init(rawValue:))) ?? .twoSpaces
        self.appearance = (defaults.string(forKey: Keys.appearance)
            .flatMap(AppearanceMode.init(rawValue:))) ?? .system
        self.editorFontDesign = (defaults.string(forKey: Keys.editorFontDesign)
            .flatMap(EditorFontDesign.init(rawValue:))) ?? .monospaced
        self.statusBarEnabled = defaults.object(forKey: Keys.statusBarEnabled) as? Bool ?? false
        self.statusShowsLineAndColumn = defaults.object(forKey: Keys.statusLineAndColumn) as? Bool ?? true
        self.statusShowsLineCount = defaults.object(forKey: Keys.statusLineCount) as? Bool ?? true
        self.statusShowsWordCount = defaults.object(forKey: Keys.statusWordCount) as? Bool ?? true
        self.statusShowsCharacterCount = defaults.object(forKey: Keys.statusCharacterCount) as? Bool ?? true
        self.statusShowsHeadingLevel = defaults.object(forKey: Keys.statusHeadingLevel) as? Bool ?? false
        self.statusShowsSelectedWordCount = defaults.object(forKey: Keys.statusSelectedWordCount) as? Bool ?? false
        self.statusShowsSelectedCharacterCount = defaults.object(forKey: Keys.statusSelectedCharacterCount) as? Bool ?? false
        self.renderSoundEnabled = defaults.object(forKey: Keys.renderSound) as? Bool ?? true
        self.smartListsEnabled = defaults.object(forKey: Keys.smartLists) as? Bool ?? true
        self.announceLineStructure = defaults.object(forKey: Keys.announceStructure) as? Bool ?? true

        let field = (defaults.string(forKey: Keys.sortField)
            .flatMap(DocumentSortField.init(rawValue:))) ?? .modified
        let direction = (defaults.string(forKey: Keys.sortDirection)
            .flatMap(SortDirection.init(rawValue:))) ?? .descending
        self.sort = DocumentSort(field: field, direction: direction)
    }

    private enum Keys {
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
        static let renderSound = "renderSoundEnabled"
        static let smartLists = "smartListsEnabled"
        static let announceStructure = "announceLineStructure"
        static let sortField = "sortField"
        static let sortDirection = "sortDirection"
    }
}
