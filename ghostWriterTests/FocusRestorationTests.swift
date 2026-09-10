//
//  FocusRestorationTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct FocusRestorationTests {

    @Test func localExplicitSaveReportsCompletion() {
        #expect(
            EditorSaveFeedback.explicitSaveMessage(
                usesICloudStorage: false
            ) == "Saved."
        )
    }

    @Test func iCloudExplicitSaveReportsBackgroundUpload() {
        #expect(
            EditorSaveFeedback.explicitSaveMessage(
                usesICloudStorage: true
            ) == "Saved. iCloud will upload changes in the background."
        )
    }
}
