//
//  AppLaunchBehavior.swift
//  ghostWriter
//
//  User-selected behavior that runs once when the Library first becomes ready.
//

import Foundation

enum AppLaunchBehavior: String, CaseIterable, Identifiable {
    case showLibrary
    case startNewDocument
    case openLastDocument

    var id: String { rawValue }

    var label: String {
        switch self {
        case .showLibrary:
            return String(localized: "Show Library")
        case .startNewDocument:
            return String(localized: "Start a New Document")
        case .openLastDocument:
            return String(localized: "Open Last Document")
        }
    }
}

/// Prevents foreground changes and view updates from repeating the launch
/// action during the same Library session.
struct AppLaunchActionGate {
    private(set) var hasPerformed = false

    mutating func begin() -> Bool {
        guard !hasPerformed else { return false }
        hasPerformed = true
        return true
    }
}
