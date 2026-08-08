//
//  NewDocumentCreationMode.swift
//  ghostWriter
//
//  Controls whether New asks for a title or uses today's date immediately.
//

import Foundation

enum NewDocumentCreationMode: String, CaseIterable, Identifiable {
    case askForTitle
    case useTodaysDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .askForTitle:
            return "Ask for a Title"
        case .useTodaysDate:
            return "Use Today’s Date"
        }
    }
}

enum NewDocumentTitle {
    static func today(
        date: Date = .now,
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
