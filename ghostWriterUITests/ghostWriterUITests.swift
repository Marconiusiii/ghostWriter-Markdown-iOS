//
//  ghostWriterUITests.swift
//  ghostWriterUITests
//
//  This target exists because the Xcode template created it, and an empty test
//  bundle fails to load. Real testing of this app happens on a physical device
//  with VoiceOver, which is the only place its accessibility behaviour can be
//  meaningfully judged — so there is deliberately no UI automation here.
//

import XCTest

final class ghostWriterUITests: XCTestCase {

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.navigationBars["ghostWriter"].waitForExistence(timeout: 10),
            "The app should launch to the library screen."
        )
    }
}
