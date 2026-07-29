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
    var editorFontDesign: EditorFontDesign
    var keyboardShortcutsEnabled: Bool

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

        textView.text = text
        textView.inputAccessoryView = makeAccessoryToolbar(coordinator: context.coordinator)
        context.coordinator.textView = textView

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

        let desiredFont = Self.editorFont(
            design: editorFontDesign,
            compatibleWith: textView.traitCollection
        )
        if textView.font?.fontName != desiredFont.fontName {
            textView.font = desiredFont
        }

        // Never write to the text view while it is being typed into. Assigning
        // `.text` resets composition state, which is precisely what breaks
        // braille screen input and dictation mid-word. External updates are
        // only applied when the view does not have focus.
        if textView.text != text, !textView.isFirstResponder {
            textView.text = text
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

            // Then hand VoiceOver focus to the editor explicitly. The sheet
            // dismissal moves focus on its own, so this has to happen after
            // that settles or it is immediately overridden.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                textView.selectedRange = target
                UIAccessibility.post(notification: .screenChanged, argument: textView)
            }

            DispatchQueue.main.async {
                // Assigning selectedRange programmatically does not reliably
                // invoke UITextViewDelegate. Mirror the same Character offset
                // into SwiftUI so the Status Bar updates with the jump instead
                // of waiting for the next manual cursor movement.
                self.selection = synchronizedSelection
                self.pendingCursorOffset = nil
            }
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
        guard characterOffset > 0 else { return 0 }
        guard characterOffset < text.count else { return text.utf16.count }
        let index = text.index(text.startIndex, offsetBy: characterOffset)
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
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
}
