//
//  MailComposerView.swift
//  ghostWriter
//
//  Presents feedback inside the system mail composer so activating the
//  Settings button does not immediately leave the app.
//

import MessageUI
import SwiftUI
import UIKit

enum FeedbackMailDraft {
    static let recipient = "marco@marconius.com"
    static let subject = "ghostWriter Markdown Feedback"

    static var currentBody: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let operatingSystem = "iOS \(UIDevice.current.systemVersion)"
        return body(appVersion: version, build: build, operatingSystem: operatingSystem)
    }

    static func body(
        appVersion: String,
        build: String,
        operatingSystem: String
    ) -> String {
        """
        App Version: \(appVersion) (\(build))
        OS: \(operatingSystem)

        Please describe your feedback below:

        """
    }
}

struct MailComposerView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (MFMailComposeResult) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController,
        context: Context
    ) {
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        let onFinish: (MFMailComposeResult) -> Void

        init(
            dismiss: DismissAction,
            onFinish: @escaping (MFMailComposeResult) -> Void
        ) {
            self.dismiss = dismiss
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result)
            dismiss()
        }
    }
}
