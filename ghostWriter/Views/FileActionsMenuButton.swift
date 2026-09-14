import SwiftUI
import UIKit

/// A native menu button with a semantic event before menu presentation.
struct FileActionsMenuButton: UIViewRepresentable {
    let makeMenu: (_ onCommandSelected: @escaping () -> Void) -> UIMenu
    let onMenuOpening: () -> Void

    func makeUIView(context: Context) -> NativeFileActionsButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = String(localized: "File Actions")
        configuration.image = UIImage(systemName: "ellipsis.circle")
        configuration.imagePadding = 6
        configuration.buttonSize = .medium
        configuration.titleLineBreakMode = .byWordWrapping
        let button = NativeFileActionsButton(configuration: configuration)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityLabel = String(localized: "File actions")
        button.showsMenuAsPrimaryAction = true
        button.onMenuOpening = onMenuOpening
        button.installMenu(makeMenu { [weak button] in button?.didSelectCommand = true })
        button.addTarget(button, action: #selector(NativeFileActionsButton.menuOpening),
                         for: .menuActionTriggered)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ button: NativeFileActionsButton, context: Context) {
        button.onMenuOpening = onMenuOpening
        button.installMenu(makeMenu { [weak button] in button?.didSelectCommand = true })
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeFileActionsButton, context: Context) -> CGSize? {
        let ideal = uiView.intrinsicContentSize
        return uiView.sizeThatFits(CGSize(width: min(proposal.width ?? ideal.width, ideal.width),
                                         height: .greatestFiniteMagnitude))
    }

}

/// Retains UIKit's menu interaction and adds completion handling for cancellation.
final class NativeFileActionsButton: UIButton {
    var onMenuOpening: (() -> Void)?
    var didSelectCommand = false
    private var menuIsPresented = false
    private var pendingMenu: UIMenu?

    func installMenu(_ updatedMenu: UIMenu) {
        if menuIsPresented {
            pendingMenu = updatedMenu
        } else {
            menu = updatedMenu
        }
    }

    @objc func menuOpening() {
        didSelectCommand = false
        menuIsPresented = true
        onMenuOpening?()
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if let animator {
            animator.addCompletion { [weak self] in self?.menuDidDismiss() }
        } else {
            menuDidDismiss()
        }
    }

    private func menuDidDismiss() {
        guard menuIsPresented else { return }
        menuIsPresented = false
        if let pendingMenu {
            menu = pendingMenu
            self.pendingMenu = nil
        }
        guard !didSelectCommand, window != nil, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .layoutChanged, argument: self)
    }
}
