//
//  FeedbackMailDraftTests.swift
//  ghostWriterTests
//
//  Verifies that diagnostic context is present without including user content.
//

import Testing
@testable import ghostWriter

struct FeedbackMailDraftTests {

    @Test func feedbackBodyIncludesAppAndOperatingSystemVersions() {
        let body = FeedbackMailDraft.body(
            appVersion: "1.2.3",
            build: "45",
            operatingSystem: "iOS 26.0"
        )

        #expect(body.contains("App Version: 1.2.3 (45)"))
        #expect(body.contains("OS: iOS 26.0"))
        #expect(body.contains("Please describe your feedback below:"))
    }

    @Test func feedbackDraftUsesTheGhostWriterIdentity() {
        #expect(FeedbackMailDraft.recipient == "marco@marconius.com")
        #expect(FeedbackMailDraft.subject == "ghostWriter Markdown Feedback")
    }
}
