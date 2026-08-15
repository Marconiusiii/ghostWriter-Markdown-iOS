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
    let session: EditorTextSession

    var smartListsEnabled: Bool
    var voiceOverVerbosity: VoiceOverVerbosity
    var editorFontDesign: EditorFontDesign
    var keyboardShortcutsEnabled: Bool
    var headingSwipeNavigationEnabled: Bool
    /// Set by the parent to move the cursor, for example from the outline.
    /// Cleared once applied.
    @Binding var pendingCursorOffset: Int?

    /// A new identifier requests the system Find and Replace navigator. An
    /// identifier instead of a Boolean ensures one request is handled once.
    @Binding var pendingFindRequest: UUID?

    /// Keyboard accessory actions. These are supplied by the editor screen and
    /// attached to the text view as its input accessory view, which is the only
    /// placement that reliably reaches a UIViewRepresentable — SwiftUI's
    /// `.keyboard` toolbar placement does not apply to a hosted UIKit view.
    var onIndent: () -> Void = {}
    var onOutdent: () -> Void = {}

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(self)
    }

    func makeUIView(context: Context) -> MarkdownEditorTextView {
        let textView = MarkdownEditorTextView()
        textView.delegate = context.coordinator
        textView.appKeyboardShortcutsEnabled = keyboardShortcutsEnabled
        textView.headingSwipeNavigationEnabled = headingSwipeNavigationEnabled

        // Monospaced for alignment, but scaled by Dynamic Type so it grows with
        // the reader's setting.
        textView.font = Self.editorFont(
            design: editorFontDesign,
            compatibleWith: textView.traitCollection
        )
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
        textView.isFindInteractionEnabled = true

        // A bare text view is announced only as "text field". Naming it says
        // what you have landed in. This is a label on a native control, not a
        // replacement for its behaviour — the value, traits, and all typing
        // feedback remain the text view's own.
        textView.accessibilityLabel = "Markdown Editor"

        session.attach(textView)
        textView.inputAccessoryView = makeAccessoryToolbar(coordinator: context.coordinator)
        context.coordinator.textView = textView
        textView.onCommittedTextInput = {
            [weak textView, weak coordinator = context.coordinator] committedText in
            guard let textView else { return }
            coordinator?.nativeTextDidCommit(
                committedText,
                in: textView
            )
        }
        textView.onHeadingSwipeSelectionChanged = { selection in
            session.updateNativeSelection(selection)
        }

        return textView
    }

    /// The bar above the on-screen keyboard: indent, outdent, and an explicit
    /// Dismiss. Built with UIBarButtonItem so it belongs to the text view's own
    /// input accessory, which means it appears for every input mode.
    private func makeAccessoryToolbar(coordinator: EditorCoordinator) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let outdent = UIBarButtonItem(
            image: UIImage(systemName: "decrease.indent"),
            style: .plain,
            target: coordinator,
            action: #selector(EditorCoordinator.handleOutdent)
        )
        outdent.accessibilityLabel = "Outdent"

        let indent = UIBarButtonItem(
            image: UIImage(systemName: "increase.indent"),
            style: .plain,
            target: coordinator,
            action: #selector(EditorCoordinator.handleIndent)
        )
        indent.accessibilityLabel = "Indent"

        let flexible = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil
        )

        let dismiss = UIBarButtonItem(
            title: "Dismiss",
            style: .done,
            target: coordinator,
            action: #selector(EditorCoordinator.handleDismissKeyboard)
        )
        dismiss.accessibilityLabel = "Dismiss keyboard"

        toolbar.items = [outdent, indent, flexible, dismiss]
        return toolbar
    }

    func updateUIView(_ textView: MarkdownEditorTextView, context: Context) {
        context.coordinator.parent = self
        if textView.appKeyboardShortcutsEnabled != keyboardShortcutsEnabled {
            textView.appKeyboardShortcutsEnabled = keyboardShortcutsEnabled
        }
        if textView.headingSwipeNavigationEnabled != headingSwipeNavigationEnabled {
            textView.headingSwipeNavigationEnabled = headingSwipeNavigationEnabled
        }

        let desiredFont = Self.editorFont(
            design: editorFontDesign,
            compatibleWith: textView.traitCollection
        )
        if textView.font?.fontName != desiredFont.fontName {
            textView.font = desiredFont
        }

        if let request = pendingFindRequest {
            DispatchQueue.main.async {
                guard self.pendingFindRequest == request else { return }
                self.pendingFindRequest = nil
                if !textView.isFirstResponder {
                    textView.becomeFirstResponder()
                }
                textView.findInteraction?.presentFindNavigator(showingReplace: true)
            }
        }

        if let offset = pendingCursorOffset {
            let currentText = textView.text ?? ""
            let synchronizedSelection = Self.selection(
                forRequestedCharacterOffset: offset,
                in: currentText
            )
            let utf16Offset = Self.utf16Offset(
                for: synchronizedSelection.location,
                in: currentText
            )
            let target = NSRange(location: utf16Offset, length: 0)

            // Take focus before moving the caret. Without this the editor never
            // becomes first responder, so after the outline sheet closes
            // VoiceOver has nothing to land on and falls back to the first
            // element on the screen — the Back button.
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }

            textView.selectedRange = target
            textView.scrollRangeToVisible(target)
            session.updateNativeSelection(target)

            // Then hand VoiceOver focus to the editor explicitly. The sheet
            // dismissal moves focus on its own, so this has to happen after
            // that settles or it is immediately overridden.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                textView.selectedRange = target
                UIAccessibility.post(notification: .screenChanged, argument: textView)
            }

            DispatchQueue.main.async { self.pendingCursorOffset = nil }
        }
    }

    /// Clamps an external cursor request to a valid Character boundary. Both
    /// Outline offsets and the Status Bar use Character counts, keeping emoji
    /// and composed characters as one position.
    static func selection(
        forRequestedCharacterOffset offset: Int,
        in text: String
    ) -> TextSelection {
        TextSelection(
            location: min(max(0, offset), text.count),
            length: 0
        )
    }

    /// Converts a Character offset to the UTF-16 offset UIKit expects.
    static func utf16Offset(for characterOffset: Int, in text: String) -> Int {
        EditorTextSession.utf16Offset(for: characterOffset, in: text)
    }

    /// Converts UIKit's UTF-16 insertion point to the Character offsets used
    /// by the outline, without splitting composed characters.
    static func characterOffset(forUTF16Offset utf16Offset: Int, in text: String) -> Int {
        let utf16 = text.utf16
        var utf16Index = utf16.index(
            utf16.startIndex,
            offsetBy: min(max(0, utf16Offset), utf16.count)
        )

        while String.Index(utf16Index, within: text) == nil,
              utf16Index > utf16.startIndex {
            utf16.formIndex(before: &utf16Index)
        }

        guard let stringIndex = String.Index(utf16Index, within: text) else {
            return 0
        }
        return text[..<stringIndex].count
    }

    /// Uses the system's already-scaled preferred body descriptor and changes
    /// only its design. Applying UIFontMetrics to preferredFont's point size
    /// would scale the same Dynamic Type preference twice at accessibility sizes.
    private static func editorFont(
        design: EditorFontDesign,
        compatibleWith traits: UITraitCollection
    ) -> UIFont {
        let preferred = UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: .body,
            compatibleWith: traits
        )

        let systemDesign: UIFontDescriptor.SystemDesign
        switch design {
        case .monospaced:
            systemDesign = .monospaced
        case .system:
            systemDesign = .default
        case .rounded:
            systemDesign = .rounded
        case .serif:
            systemDesign = .serif
        }

        let descriptor = preferred.withDesign(systemDesign) ?? preferred
        return UIFont(descriptor: descriptor, size: 0)
    }
}

final class MarkdownEditorTextView: UITextView {
    var appKeyboardShortcutsEnabled = true
    var headingSwipeNavigationEnabled = true
    var onCommittedTextInput: ((String) -> Void)?
    var onHeadingSwipeSelectionChanged: ((NSRange) -> Void)?
    private(set) var isPerformingPaste = false

    override func accessibilityScroll(
        _ direction: UIAccessibilityScrollDirection
    ) -> Bool {
        guard headingSwipeNavigationEnabled else {
            return super.accessibilityScroll(direction)
        }

        let headingDirection: HeadingNavigationDirection
        switch direction {
        case .right:
            headingDirection = .next
        case .left:
            headingDirection = .previous
        default:
            return super.accessibilityScroll(direction)
        }

        moveToHeading(headingDirection)
        return true
    }

    private func moveToHeading(_ direction: HeadingNavigationDirection) {
        let currentText = text ?? ""
        let entries = OutlineBuilder.build(from: currentText)

        guard !entries.isEmpty else {
            postHeadingPosition("No headings.")
            return
        }

        let characterOffset = MarkdownTextView.characterOffset(
            forUTF16Offset: selectedRange.location,
            in: currentText
        )
        guard let destination = OutlineBuilder.destination(
            in: entries,
            from: characterOffset,
            moving: direction
        ) else {
            switch direction {
            case .next:
                postHeadingPosition("No next heading.")
            case .previous:
                postHeadingPosition("No previous heading.")
            }
            return
        }

        let target = NSRange(
            location: MarkdownTextView.utf16Offset(
                for: destination.characterOffset,
                in: currentText
            ),
            length: 0
        )
        selectedRange = target
        scrollRangeToVisible(target)
        onHeadingSwipeSelectionChanged?(target)

        guard let position = entries.firstIndex(of: destination) else { return }
        let title = destination.title.isEmpty ? "Empty heading" : destination.title
        postHeadingPosition(
            "Heading \(position + 1) of \(entries.count), \(title), heading level \(destination.level)."
        )
    }

    private func postHeadingPosition(_ description: String) {
        UIAccessibility.post(notification: .announcement, argument: description)
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        if appKeyboardShortcutsEnabled {
            commands.append(
                UIKeyCommand(
                    title: "Dismiss Keyboard",
                    action: #selector(dismissKeyboardCommand),
                    input: UIKeyCommand.inputEscape,
                    modifierFlags: []
                )
            )
        }
        return commands
    }

    @objc private func dismissKeyboardCommand() {
        resignFirstResponder()
    }

    override func paste(_ sender: Any?) {
        isPerformingPaste = true
        super.paste(sender)
        isPerformingPaste = false
    }

    override func insertText(_ text: String) {
        super.insertText(text)
        guard !isPerformingPaste else { return }
        onCommittedTextInput?(text)
    }

    override func unmarkText() {
        let committedText = markedTextRange.flatMap { text(in: $0) }
        super.unmarkText()
        guard let committedText, !committedText.isEmpty,
              !isPerformingPaste else { return }
        onCommittedTextInput?(committedText)
    }
}
