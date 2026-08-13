//
//  AccessibleControlStyles.swift
//  ghostWriter
//
//  Color pairings for native controls whose tint becomes a filled surface.
//

import SwiftUI

extension View {
    /// Keeps SwiftUI's native prominent button behavior while pairing its
    /// filled tint with a foreground that meets WCAG contrast in both system
    /// appearances. The general app accent remains available for text, links,
    /// insertion points, and unfilled controls.
    func ghostProminentButtonStyle() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .tint(Color.controlFill)
            .foregroundStyle(Color.white)
    }

    /// Gives native filled controls a tint that remains distinguishable from
    /// both their light content and the surrounding surface.
    func ghostFilledControlTint() -> some View {
        self.tint(Color.controlFill)
    }
}
