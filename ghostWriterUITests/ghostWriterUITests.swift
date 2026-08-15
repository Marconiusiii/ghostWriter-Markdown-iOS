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
    func testVoiceOverVerbosityUsesConciseScalableOptions() throws {
        let app = launchLibraryApp(
            additionalArguments: [
                "-voiceOverVerbosity",
                "light"
            ]
        )
        app.buttons["Settings"].tap()

        let lightDescription = app.staticTexts[
            "Announces list changes, indentation levels, and Insert actions."
        ]
        for _ in 0..<5 where !lightDescription.exists {
            app.swipeUp()
        }
        XCTAssertTrue(lightDescription.waitForExistence(timeout: 5))

        let verbosityGroup = app.otherElements["Verbosity"]
        XCTAssertTrue(verbosityGroup.waitForExistence(timeout: 10))
        let picker = verbosityGroup.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Off"].exists)
        XCTAssertTrue(picker.buttons["Light"].exists)
        XCTAssertTrue(picker.buttons["Full"].exists)
        XCTAssertTrue(lightDescription.exists)

        picker.buttons["Off"].tap()
        XCTAssertTrue(
            app.staticTexts["No Markdown editing announcements."]
                .waitForExistence(timeout: 5)
        )

        picker.buttons["Full"].tap()
        XCTAssertTrue(
            app.staticTexts[
                "Announces Light feedback and completed Markdown structures as you type."
            ].waitForExistence(timeout: 5)
        )

        app.terminate()

        let largeTextApp = launchLibraryApp(
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
                "-voiceOverVerbosity",
                "light"
            ]
        )
        largeTextApp.buttons["Settings"].tap()
        let largeTextDescription = largeTextApp.staticTexts[
            "Announces list changes, indentation levels, and Insert actions."
        ]
        for _ in 0..<5 where !largeTextDescription.exists {
            largeTextApp.swipeUp()
        }
        XCTAssertTrue(largeTextDescription.waitForExistence(timeout: 5))
        let largeTextGroup = largeTextApp.otherElements["Verbosity"]
        XCTAssertTrue(largeTextGroup.waitForExistence(timeout: 5))
        let largeTextPicker = largeTextGroup.segmentedControls.firstMatch
        XCTAssertTrue(largeTextPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(largeTextPicker.buttons["Off"].exists)
        XCTAssertTrue(largeTextPicker.buttons["Light"].exists)
        XCTAssertTrue(largeTextPicker.buttons["Full"].exists)
    }

    @MainActor
    func testDocumentRowProvidesActionsWithoutASeparateMenuStop() throws {
        let app = launchLibraryApp()
        let name = "Row Actions \(UUID().uuidString)"

        app.buttons["New document"].tap()
        let nameField = app.textFields["Document name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Create"].tap()

        let editor = app.textViews["Markdown Editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.buttons["Back"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", name)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Actions for \(name)"].exists)

        row.press(forDuration: 1)
        for action in [
            "Pin", "Render", "Share", "Rename", "Move", "Duplicate", "Delete"
        ] {
            XCTAssertTrue(
                app.buttons[action].waitForExistence(timeout: 5),
                "The document context menu should contain \(action)."
            )
        }
        XCTAssertEqual(
            app.buttons.matching(identifier: "Pin").count,
            1,
            "The document context menu should expose Pin once."
        )
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.alerts["Rename Document"].waitForExistence(timeout: 5))
        app.alerts["Rename Document"].buttons["Cancel"].tap()

        row.swipeLeft()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete"].exists)
        row.swipeRight()
        row.swipeRight()
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 5))
        row.swipeLeft()

        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
    }

    @MainActor
    func testFolderRowProvidesActionsWithoutASeparateMenuStop() throws {
        let app = launchLibraryApp()
        let name = "Folder Actions \(UUID().uuidString)"

        app.buttons["New Folder"].tap()
        let nameField = app.textFields["Folder Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Create"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", name)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Actions for \(name)"].exists)

        row.press(forDuration: 1)
        for action in ["Rename", "Move", "Delete"] {
            XCTAssertTrue(
                app.buttons[action].waitForExistence(timeout: 5),
                "The folder context menu should contain \(action)."
            )
        }
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.alerts["Rename Folder"].waitForExistence(timeout: 5))
        app.alerts["Rename Folder"].buttons["Cancel"].tap()

        row.swipeLeft()
        XCTAssertTrue(app.buttons["Move"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete"].exists)
        row.swipeRight()
        row.swipeRight()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        row.swipeLeft()

        row.tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
    }

    @MainActor
    func testPrimaryControlsRenderInLightAndDarkAppearances() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-documentStorageLocation", "onDevice",
                "-appLaunchBehavior", "showLibrary",
                "-newDocumentCreationMode", "askForTitle",
                "-welcomeExperienceCompleted", "YES",
                "-welcomeDocumentInstalled", "YES",
                "-appearance", appearance
            ]
            app.launch()

            let newDocument = app.buttons["New document"]
            XCTAssertTrue(newDocument.waitForExistence(timeout: 10))
            attachScreenshot(
                app,
                name: "Library primary controls, \(appearance) appearance"
            )

            app.buttons["Settings"].tap()
            let automaticLists = app.switches["Automatic Lists"]
            XCTAssertTrue(automaticLists.waitForExistence(timeout: 10))
            attachScreenshot(
                app,
                name: "Settings filled controls, \(appearance) appearance"
            )

            app.terminate()
        }
    }

    @MainActor
    func testPrimaryControlsFollowSystemAppearance() throws {
        let expectedAppearance = ProcessInfo.processInfo.environment[
            "GHOSTWRITER_SYSTEM_APPEARANCE"
        ] ?? "current system"
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "showLibrary",
            "-newDocumentCreationMode", "askForTitle",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES",
            "-appearance", "system"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["New document"].waitForExistence(timeout: 10))
        attachScreenshot(
            app,
            name: "Library controls, following \(expectedAppearance)"
        )

        app.buttons["Settings"].tap()
        XCTAssertTrue(
            app.switches["Automatic Lists"].waitForExistence(timeout: 10)
        )
        attachScreenshot(
            app,
            name: "Settings controls, following \(expectedAppearance)"
        )
    }

    @MainActor
    func testSecondReturnExitsAutomaticList() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "showLibrary",
            "-newDocumentCreationMode", "askForTitle",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
        ]
        app.launch()

        app.buttons["New document"].tap()
        let nameField = app.textFields["Document name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("List Return \(UUID().uuidString)")
        app.buttons["Create"].tap()

        let editor = app.textViews["Markdown Editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("* First\n\nParagraph")

        XCTAssertEqual(editor.value as? String, "* First\nParagraph")
    }

    @MainActor
    func testSustainedTypingIsSavedWhenEditorCloses() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "showLibrary",
            "-newDocumentCreationMode", "askForTitle",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
        ]
        app.launch()

        app.buttons["New document"].tap()
        let name = "Typing Boundary \(UUID().uuidString)"
        let nameField = app.textFields["Document name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Create"].tap()

        let editor = app.textViews["Markdown Editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let contents = String(repeating: "braille typing remains responsive ", count: 10)
        editor.tap()
        editor.typeText(contents)
        app.buttons["Back"].tap()

        let document = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", name)
        ).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 10))
        document.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, contents)
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "showLibrary",
            "-newDocumentCreationMode", "askForTitle",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
        ]
        app.launch()
        // The heading is ordinary content rather than a navigation title, so
        // that reading order follows code order.
        XCTAssertTrue(
            app.staticTexts["ghostWriter Markdown"].waitForExistence(timeout: 10),
            "The app should launch to the library screen."
        )
        XCTAssertFalse(app.textFields["Document name"].exists)
        XCTAssertFalse(app.buttons["File actions"].exists)
    }

    @MainActor
    func testAppLaunchCanStartWithTheNamingScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "startNewDocument",
            "-newDocumentCreationMode", "askForTitle",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
        ]

        app.launch()

        XCTAssertTrue(
            app.textFields["Document name"].waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.buttons["File actions"].exists)
    }

    @MainActor
    func testAppLaunchCanCreateATodayDocumentImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "startNewDocument",
            "-newDocumentCreationMode", "useTodaysDate",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
        ]

        app.launch()

        XCTAssertTrue(
            app.buttons["File actions"].waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.textFields["Document name"].exists)
    }

    @MainActor
    func testLibraryCommandsRemainAvailableAtLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
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
        app.launchArguments += [
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
        ]
        app.launch()

        app.buttons["New document"].tap()

        let nameField = app.textFields["Document name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
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

    @MainActor
    func testFirstLaunchWelcomePrecedesConfiguredLaunchBehavior() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "startNewDocument",
            "-newDocumentCreationMode", "askForTitle",
            "-welcomeExperienceCompleted", "NO",
            "-welcomeDocumentInstalled", "NO"
        ]

        app.launch()

        XCTAssertTrue(
            app.staticTexts["Welcome to ghostWriter Markdown"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["Explore Welcome Document"].exists)
        XCTAssertTrue(app.buttons["Continue to Library"].exists)
        XCTAssertFalse(app.textFields["Document name"].exists)

        app.buttons["Continue to Library"].tap()
        XCTAssertTrue(
            app.staticTexts["ghostWriter Markdown"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.textFields["Document name"].exists)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchLibraryApp(
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "showLibrary",
            "-newDocumentCreationMode", "askForTitle",
            "-welcomeExperienceCompleted", "YES",
            "-welcomeDocumentInstalled", "YES"
        ]
        app.launchArguments += additionalArguments
        app.launch()
        XCTAssertTrue(app.buttons["New document"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testWelcomeDocumentCanBeOpenedForExploration() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-documentStorageLocation", "onDevice",
            "-appLaunchBehavior", "showLibrary",
            "-welcomeExperienceCompleted", "NO",
            "-welcomeDocumentInstalled", "NO"
        ]

        app.launch()

        let explore = app.buttons["Explore Welcome Document"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == YES"),
            object: explore
        )
        wait(for: [ready], timeout: 10)
        explore.tap()

        XCTAssertTrue(
            app.buttons["File actions"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.staticTexts["Welcome to ghostWriter Markdown"].exists
        )
    }
}
