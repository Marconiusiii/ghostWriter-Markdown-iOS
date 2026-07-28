//
//  MarkdownTextView.swift
//  ghostWriter
//
//  A UITextView hosted in SwiftUI. SwiftUI's TextEditor exposes no cursor or
//  selection, which rules out indentation controls and jump-to-heading.
//
//  The guiding rule here: this is a raw markdown text field and nothing more.
//  No accessibility label overrides, no accessibility value, no announcements,
//  no re-rendering of the user's text. UITextView already has years of work
//  behind its VoiceOver, braille screen input, and hardware keyboard support,
//  and every layer added on top of it is a layer that can break those.
//

import SwiftUI
import UIKit

struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection

    var smartListsEnabled: Bool

    /// Set by the parent to move the cursor, for example from the outline.
    /// Cleared once applied.
    @Binding var pendingCursorOffset: Int?

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator

        // Monospaced for alignment, but scaled by Dynamic Type so it grows with
        // the reader's setting.
        let body = UIFont.preferredFont(forTextStyle: .body)
        let monospaced = UIFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
        textView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: monospaced)
        textView.adjustsFontForContentSizeCategory = true

        textView.backgroundColor = UIColor(named: "EditorBackground") ?? .systemBackground
        textView.textColor = UIColor(named: "GhostText") ?? .label
        textView.tintColor = UIColor(named: "GhostAccent") ?? .tintColor

        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)

        // Markdown is punctuation that must survive exactly as typed. Smart
        // quotes and smart dashes silently corrupt link and code syntax.
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .default

        textView.text = text

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        // Never write to the text view while it is being typed into. Assigning
        // `.text` resets composition state, which is precisely what breaks
        // braille screen input and dictation mid-word. External updates are
        // only applied when the view does not have focus.
        if textView.text != text, !textView.isFirstResponder {
            textView.text = text
        }

        if let offset = pendingCursorOffset {
            let utf16Offset = Self.utf16Offset(for: offset, in: textView.text ?? "")
            let target = NSRange(location: utf16Offset, length: 0)
            textView.selectedRange = target
            textView.scrollRangeToVisible(target)

            DispatchQueue.main.async {
                self.pendingCursorOffset = nil
            }
        }
    }

    /// Converts a Character offset to the UTF-16 offset UIKit expects.
    static func utf16Offset(for characterOffset: Int, in text: String) -> Int {
        guard characterOffset > 0 else { return 0 }
        guard characterOffset < text.count else { return text.utf16.count }
        let index = text.index(text.startIndex, offsetBy: characterOffset)
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }
}
