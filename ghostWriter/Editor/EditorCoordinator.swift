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
    private var isApplyingSmartListEdit = false
    private var pendingMarkedListReturn: DeferredListReturnPlan?

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
        if isApplyingSmartListEdit { return true }

        // A prior marked-text plan must never leak into a later edit if UIKit
        // did not deliver the expected change callback.
        pendingMarkedListReturn = nil

        if textView.markedTextRange != nil,
           parent.smartListsEnabled,
           range.length == 0,
           let plan = ListContinuation.deferredReturnPlan(
            in: textView.text ?? "",
            utf16Cursor: range.location,
            replacementText: replacementText
           ) {
            // Let Braille Screen Input commit its marked text and Return using
            // UIKit's native path. The minimal list edit follows in
            // textViewDidChange, after composition has completed.
            pendingMarkedListReturn = plan
            parent.session.willApplyEdit(
                range: range,
                replacementText: replacementText
            )
            return true
        }

        // Marked text other than a list Return remains completely native.
        if textView.markedTextRange != nil {
            parent.session.willApplyEdit(
                range: range,
                replacementText: replacementText
            )
            return true
        }

        guard parent.smartListsEnabled,
              ListContinuation.isReturn(replacementText),
              range.length == 0 else {
            parent.session.willApplyEdit(
                range: range,
                replacementText: replacementText
            )
            return true
        }

        let text = textView.text ?? ""
        let nsText = text as NSString

        // Find the line the caret sits on, working in UTF-16 because that is
        // what UIKit hands us.
        let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        var line = nsText.substring(with: lineRange)
        while line.last == "\n" || line.last == "\r" { line.removeLast() }

        guard let marker = ListMarker(line: line) else {
            parent.session.willApplyEdit(
                range: range,
                replacementText: replacementText
            )
            return true
        }

        if marker.content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: clear the marker so the list ends. Replace just this
            // line, not the document.
            let lineLength = line.utf16.count
            let replaceRange = NSRange(location: lineRange.location, length: lineLength)
            if let textRange = textRange(in: textView, from: replaceRange) {
                parent.session.willApplyEdit(range: replaceRange, replacementText: "")
                isApplyingSmartListEdit = true
                textView.replace(textRange, withText: "")
                isApplyingSmartListEdit = false
            }
            announce("List ended")
        } else {
            // Continue the list by inserting only the newline and next marker
            // at the caret. `insertText` goes through the normal input path, so
            // undo, autocorrect state, and assistive input all behave.
            let insertion = "\n" + marker.nextItemPrefix
            parent.session.willApplyEdit(range: range, replacementText: insertion)
            isApplyingSmartListEdit = true
            textView.insertText(insertion)
            isApplyingSmartListEdit = false
            announce(continuationAnnouncement(for: marker))
        }

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
        applyPendingMarkedListReturn(in: textView)
        parent.session.textDidChange(in: textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        parent.session.selectionDidChange(in: textView)
    }

    private func applyPendingMarkedListReturn(in textView: UITextView) {
        guard let plan = pendingMarkedListReturn else { return }
        pendingMarkedListReturn = nil
        guard let edit = ListContinuation.editAfterNativeReturn(
            plan,
            in: textView.text ?? "",
            selectedRange: textView.selectedRange
        ), let textRange = textRange(
            in: textView,
            from: edit.range
        ) else { return }

        isApplyingSmartListEdit = true
        textView.replace(textRange, withText: edit.replacementText)
        textView.selectedRange = edit.selectedRange
        isApplyingSmartListEdit = false
        parent.session.updateNativeSelection(edit.selectedRange)

        switch plan.action {
        case .continueList:
            announce(continuationAnnouncement(for: plan.marker))
        case .endList:
            announce("List ended")
        }
    }
}
