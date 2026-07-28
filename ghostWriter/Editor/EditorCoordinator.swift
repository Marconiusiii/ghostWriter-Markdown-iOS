//
//  EditorCoordinator.swift
//  ghostWriter
//
//  The UITextViewDelegate behind MarkdownTextView.
//
//  This deliberately does almost nothing. The editor is raw markdown and the
//  text view owns its own text, its own selection, and its own speech. Earlier
//  versions of this file rewrote the whole document to continue lists and set
//  an accessibility value as the caret moved; both broke braille screen input
//  and fought what VoiceOver was already saying. Neither is worth it.
//
//  The one remaining behaviour is list continuation, and it is implemented as a
//  small insertion at the caret rather than a document replacement, so the text
//  view's own input machinery stays intact.
//

import SwiftUI
import UIKit

@MainActor
final class EditorCoordinator: NSObject, UITextViewDelegate {
    var parent: MarkdownTextView
    weak var textView: UITextView?

    init(_ parent: MarkdownTextView) {
        self.parent = parent
    }

    // MARK: - Typing

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText: String
    ) -> Bool {
        // Multi-stage input — braille screen input composing a word, dictation,
        // or an input method editor — must be left completely alone. Touching
        // the text mid-composition is what breaks these input modes.
        if textView.markedTextRange != nil { return true }

        guard parent.smartListsEnabled else { return true }
        guard replacementText == "\n", range.length == 0 else { return true }

        let text = textView.text ?? ""
        let nsText = text as NSString

        // Find the line the caret sits on, working in UTF-16 because that is
        // what UIKit hands us.
        let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        var line = nsText.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }

        guard let marker = ListMarker(line: line) else { return true }

        if marker.content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: clear the marker so the list ends. Replace just this
            // line, not the document.
            let lineLength = line.utf16.count
            let replaceRange = NSRange(location: lineRange.location, length: lineLength)
            if let textRange = textRange(in: textView, from: replaceRange) {
                textView.replace(textRange, withText: "")
            }
        } else {
            // Continue the list by inserting only the newline and next marker
            // at the caret. `insertText` goes through the normal input path, so
            // undo, autocorrect state, and assistive input all behave.
            textView.insertText("\n" + marker.nextItemPrefix)
        }

        parent.text = textView.text ?? ""
        return false
    }

    private func textRange(in textView: UITextView, from nsRange: NSRange) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: nsRange.location),
              let end = textView.position(from: start, offset: nsRange.length) else { return nil }
        return textView.textRange(from: start, to: end)
    }

    func textViewDidChange(_ textView: UITextView) {
        parent.text = textView.text ?? ""
        syncSelection(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        syncSelection(textView)
    }

    /// Mirrors the selection out to SwiftUI so the indent controls know what to
    /// operate on. Nothing is spoken and nothing is written back.
    private func syncSelection(_ textView: UITextView) {
        let text = textView.text ?? ""
        let range = textView.selectedRange
        let location = characterOffset(for: range.location, in: text)
        let end = characterOffset(for: range.location + range.length, in: text)
        parent.selection = TextSelection(location: location, length: max(0, end - location))
    }

    // MARK: - Offset conversion

    /// UIKit reports offsets in UTF-16 code units; our editing helpers work in
    /// Characters. These differ as soon as a document contains an emoji or a
    /// combining accent, so the crossing is done explicitly.
    private func characterOffset(for utf16Offset: Int, in text: String) -> Int {
        guard utf16Offset > 0 else { return 0 }
        let utf16 = text.utf16
        guard utf16Offset < utf16.count else { return text.count }

        guard let index = utf16.index(
            utf16.startIndex,
            offsetBy: utf16Offset,
            limitedBy: utf16.endIndex
        ), let stringIndex = String.Index(index, within: text) else {
            return text.count
        }

        return text.distance(from: text.startIndex, to: stringIndex)
    }
}
