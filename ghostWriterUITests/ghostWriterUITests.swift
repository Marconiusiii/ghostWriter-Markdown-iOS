//
//  ghostWriterUITests.swift
//  ghostWriterUITests
//
//  UI automation checks that critical controls and presentation paths remain
//  available. Physical-device VoiceOver testing remains the authority for
//  spoken order, focus timing, and assistive-technology behaviour.
//

import XCTest

final class ghostWriterUITests: XCTestCase {

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        // The heading is ordinary content rather than a navigation title, so
        // that reading order follows code order.
        XCTAssertTrue(
            app.staticTexts["ghostWriter Markdown"].waitForExistence(timeout: 10),
            "The app should launch to the library screen."
        )
    }

    @MainActor
    func testLibraryCommandsRemainAvailableAtLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New document"].exists)
        XCTAssertTrue(app.buttons["Import document"].exists)

        let deleted = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Deleted,")
        ).firstMatch
        XCTAssertTrue(deleted.exists)

        let search = app.textFields["Search"]
        if !search.exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            search.waitForExistence(timeout: 5),
            "The scrolling Library should keep Search reachable at the largest text size."
        )
    }

    @MainActor
    func testJumpToLineReportsAnUnavailableLine() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["New document"].tap()

        let nameField = app.textFields["Document name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Jump Test \(UUID().uuidString)")
        app.buttons["Create"].tap()

        let fileActions = app.buttons["File actions"]
        XCTAssertTrue(fileActions.waitForExistence(timeout: 5))
        fileActions.tap()
        app.buttons["Jump to Line…"].tap()

        let lineField = app.textFields["Line number"]
        XCTAssertTrue(lineField.waitForExistence(timeout: 5))
        lineField.typeText("99")
        app.buttons["Jump"].tap()

        XCTAssertTrue(
            app.staticTexts["Line Does Not Exist"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Line 99 does not exist. This document has 1 line."]
                .exists
        )
    }
}
