//
//  DateFormatting.swift
//  ghostWriter
//
//  Dates appear on every row in the library, so they are formatted two ways:
//  a compact form for display, and a fuller spoken form for VoiceOver. A date
//  rendered as "7/27/26" is fine to glance at but is read aloud awkwardly, so
//  the accessibility label uses a natural phrasing instead.
//

import Foundation

enum DateFormatting {

    /// Compact display form, relative for recent dates ("Yesterday") and
    /// numeric for older ones.
    static func short(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named

        // Within the last week a relative description is more useful than a
        // date; beyond that an absolute date is clearer.
        if let days = Calendar.current.dateComponents([.day], from: date, to: .now).day,
           days < 7, days >= 0 {
            return formatter.localizedString(for: date, relativeTo: .now)
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Fuller phrasing for VoiceOver, e.g. "27 July 2026 at 4:15 PM".
    static func spoken(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }
}
