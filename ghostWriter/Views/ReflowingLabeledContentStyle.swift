//
//  ReflowingLabeledContentStyle.swift
//  ghostWriter
//
//  The form row layout used wherever a control needs a visible label.
//
//  A placeholder is not a label: it vanishes the moment there is a value,
//  leaving a field no one can identify afterwards. LabeledContent is the fix —
//  it renders the label visibly, keeps it out of the VoiceOver focus order as
//  a stop of its own, and folds it into what the control announces. Controls
//  wrapped in one must pass no label of their own, or the row is named twice
//  and VoiceOver reads both.
//

import SwiftUI

/// Lays a labelled row out horizontally at normal text sizes and vertically at
/// accessibility sizes.
///
/// This exists because the built-in `.vertical` style cannot be used: it breaks
/// VoiceOver's double-tap activation on a text field, leaving the field visible
/// but impossible to open. Styling `LabeledContent` ourselves keeps the label
/// folded into the control the way the automatic style does — one focus stop,
/// label spoken with the control — while still letting the row reflow.
///
/// `AnyLayout` rather than an if/else so the views keep their identity across
/// the switch. A control that is re-created loses focus, and a control that
/// loses focus takes VoiceOver's place on the screen with it.
struct ReflowingLabeledContentStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))

        layout {
            configuration.label
                .multilineTextAlignment(.leading)
                // The label takes only the width its text needs, so the
                // control gets the rest of the row rather than being squeezed
                // out of it.
                .layoutPriority(1)

            configuration.content
                // The control fills the remaining width in both arrangements.
                //
                // A greedy Spacer here instead would collapse an empty text
                // field to nothing: a field with no text has almost no
                // intrinsic width, so the Spacer takes the whole row and
                // leaves a sliver too small to tap or to focus. Giving the
                // content the width directly keeps the field a real target
                // even when it is empty.
                .frame(
                    maxWidth: .infinity,
                    alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
                )
        }
    }
}
