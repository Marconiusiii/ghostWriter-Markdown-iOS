//
//  EditorTextSession.swift
//  ghostWriter
//
//  Keeps UITextView authoritative while the writer is typing. Ordinary edits
//  perform no copying, dispatch, persistence, or observable work. A complete
//  UIKit snapshot is created only when an explicit action requests it.
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
    let documentBuffer: EditorDocumentBuffer

    private(set) var revision = 0

    init(
        initialText: String,
        documentBuffer: EditorDocumentBuffer? = nil
    ) {
        self.storedText = initialText
        self.documentBuffer = documentBuffer
            ?? EditorDocumentBuffer(initialText: initialText)
    }

    func attach(_ textView: UITextView) {
        self.textView = textView
        textView.text = storedText
        storedSelectedRange = textView.selectedRange
    }

    /// Called before UIKit applies an accepted native edit. A revision counter
    /// is the only app-owned work on the ordinary typing path.
    func willApplyEdit(
        range _: NSRange,
        replacementText _: String
    ) {
        revision &+= 1
    }

    func textDidChange(in textView: UITextView) {
        storedSelectedRange = textView.selectedRange
    }

    /// Selection changes can be frequent during Braille composition. Store the
    /// native UTF-16 range without copying or scanning the document.
    func selectionDidChange(in textView: UITextView) {
        storedSelectedRange = textView.selectedRange
    }

    /// Used only at an explicit action boundary.
    func snapshot() -> EditorTextSnapshot {
        let text = textView?.text ?? storedText
        let range = textView?.selectedRange ?? storedSelectedRange
        storedText = text
        storedSelectedRange = range
        documentBuffer.replace(
            text: text,
            revision: revision
        )
        return EditorTextSnapshot(
            text: text,
            selection: Self.selection(for: range, in: text),
            revision: revision
        )
    }

    /// Applies a deliberate transformation such as Indent, Insert, or conflict
    /// reload. This is never used to mirror ordinary typing back into UIKit.
    func replaceText(_ text: String, selection: TextSelection) {
        storedText = text
        revision &+= 1
        let range = Self.utf16Range(for: selection, in: text)
        storedSelectedRange = range
        textView?.text = text
        textView?.selectedRange = range
        textView?.scrollRangeToVisible(range)
        documentBuffer.replace(
            text: text,
            revision: revision
        )
    }

    func updateNativeSelection(_ range: NSRange) {
        storedSelectedRange = range
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
