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
    private var editGeneration = 0
    private var lastSyncedEditGeneration = -1
    private var lastSyncedRange: NSRange?

    init(_ parent: MarkdownTextView) {
        self.parent = parent
    }

    // MARK: - Keyboard accessory actions

    @objc func handleIndent() {
        parent.onIndent()
    }

    @objc func handleOutdent() {
        parent.onOutdent()
    }

    @objc func handleDismissKeyboard() {
        textView?.resignFirstResponder()
    }

    /// Puts the keyboard away from outside the text view, used before showing a
    /// menu or sheet so it does not sit over the presented content.
    func dismissKeyboard() {
        textView?.resignFirstResponder()
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
            announce("List ended")
        } else {
            // Continue the list by inserting only the newline and next marker
            // at the caret. `insertText` goes through the normal input path, so
            // undo, autocorrect state, and assistive input all behave.
            textView.insertText("\n" + marker.nextItemPrefix)
            announce(continuationAnnouncement(for: marker))
        }

        parent.text = textView.text ?? ""
        return false
    }

    /// Describes the item that was just created. Without this the only feedback
    /// is the boundary-reached tone, which says nothing about what happened.
    private func continuationAnnouncement(for marker: ListMarker) -> String {
        let depth = LineAnalyzer.indentColumns(of: marker.indent) / 2

        let base: String
        switch marker.style {
        case .unordered:
            base = marker.taskBox != nil ? "Task added" : "Bullet added"
        case .ordered(let number):
            base = "Item \(number + 1) added"
        }

        return depth > 0 ? "\(base), level \(depth + 1)" : base
    }

    /// Speaks a short state change. This fires only on a deliberate structural
    /// transition — creating or ending a list item — never while typing
    /// ordinary text, so it does not talk over the user's own input echo.
    private func announce(_ message: String) {
        // A brief delay lets the text view finish its own edit announcement
        // first, so the two do not collide and cut each other off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func textRange(in textView: UITextView, from nsRange: NSRange) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: nsRange.location),
              let end = textView.position(from: start, offset: nsRange.length) else { return nil }
        return textView.textRange(from: start, to: end)
    }

    func textViewDidChange(_ textView: UITextView) {
        editGeneration += 1
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
        guard editGeneration != lastSyncedEditGeneration
                || range != lastSyncedRange else { return }

        let location = characterOffset(for: range.location, in: text)
        let end = characterOffset(for: range.location + range.length, in: text)
        parent.selection = TextSelection(location: location, length: max(0, end - location))
        lastSyncedEditGeneration = editGeneration
        lastSyncedRange = range
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
