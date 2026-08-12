//
//  EditorTextSession.swift
//  ghostWriter
//
//  Keeps UITextView authoritative while the writer is typing. Ordinary text
//  and selection delegate callbacks update only inexpensive native state; a
//  complete Swift String snapshot is created after an idle boundary or when an
//  explicit editor action requests one.
//

import Foundation
import UIKit

nonisolated struct EditorTextSnapshot: Equatable, Sendable {
    let text: String
    let selection: TextSelection
    let revision: Int
}

@MainActor
final class EditorTextSession {
    private weak var textView: UITextView?
    private var storedText: String
    private var storedSelectedRange = NSRange(location: 0, length: 0)
    private var idleTimer: Timer?
    private let idleDelay: TimeInterval

    private(set) var revision = 0
    var onIdleSnapshot: ((EditorTextSnapshot) -> Void)?

    init(
        initialText: String,
        idleDelay: TimeInterval = 1
    ) {
        self.storedText = initialText
        self.idleDelay = idleDelay
    }

    deinit {
        idleTimer?.invalidate()
    }

    func attach(_ textView: UITextView) {
        self.textView = textView
        textView.text = storedText
        storedSelectedRange = textView.selectedRange
    }

    /// Called by UITextViewDelegate for an ordinary native edit. This must stay
    /// constant-time with respect to document length.
    func textDidChange(in textView: UITextView) {
        revision &+= 1
        storedSelectedRange = textView.selectedRange
        scheduleIdleSnapshot()
    }

    /// Selection changes can be frequent during Braille composition. Store the
    /// native UTF-16 range without copying or scanning the document.
    func selectionDidChange(in textView: UITextView) {
        storedSelectedRange = textView.selectedRange
    }

    /// Used only at an idle or explicit action boundary.
    func snapshot() -> EditorTextSnapshot {
        let text = textView?.text ?? storedText
        let range = textView?.selectedRange ?? storedSelectedRange
        storedText = text
        storedSelectedRange = range
        return EditorTextSnapshot(
            text: text,
            selection: Self.selection(for: range, in: text),
            revision: revision
        )
    }

    /// Applies a deliberate transformation such as Indent, Insert, or conflict
    /// reload. This is never used to mirror ordinary typing back into UIKit.
    func replaceText(_ text: String, selection: TextSelection) {
        idleTimer?.invalidate()
        storedText = text
        revision &+= 1
        let range = Self.utf16Range(for: selection, in: text)
        storedSelectedRange = range
        textView?.text = text
        textView?.selectedRange = range
        textView?.scrollRangeToVisible(range)
    }

    func updateNativeSelection(_ range: NSRange) {
        storedSelectedRange = range
    }

    func cancelIdleSnapshot() {
        idleTimer?.invalidate()
    }

    private func scheduleIdleSnapshot() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: idleDelay,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Never inspect or publish a document while a multi-stage
                // input method still owns marked text. Try again after it
                // settles.
                if self.textView?.markedTextRange != nil {
                    self.scheduleIdleSnapshot()
                    return
                }

                self.onIdleSnapshot?(self.snapshot())
            }
        }
    }

    static func selection(for range: NSRange, in text: String) -> TextSelection {
        let safeLocation = min(max(0, range.location), text.utf16.count)
        let safeEnd = min(
            max(safeLocation, range.location + range.length),
            text.utf16.count
        )
        let location = characterOffset(for: safeLocation, in: text)
        let end = characterOffset(for: safeEnd, in: text)
        return TextSelection(location: location, length: max(0, end - location))
    }

    static func utf16Range(for selection: TextSelection, in text: String) -> NSRange {
        let safeLocation = min(max(0, selection.location), text.count)
        let safeEnd = min(
            max(safeLocation, selection.location + selection.length),
            text.count
        )
        let location = utf16Offset(for: safeLocation, in: text)
        let end = utf16Offset(for: safeEnd, in: text)
        return NSRange(location: location, length: max(0, end - location))
    }

    static func utf16Offset(for characterOffset: Int, in text: String) -> Int {
        guard characterOffset > 0 else { return 0 }
        guard characterOffset < text.count else { return text.utf16.count }
        let index = text.index(text.startIndex, offsetBy: characterOffset)
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }

    private static func characterOffset(for utf16Offset: Int, in text: String) -> Int {
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
