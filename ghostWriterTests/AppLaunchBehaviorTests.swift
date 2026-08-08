//
//  AppLaunchBehaviorTests.swift
//  ghostWriterTests
//


import Testing
@testable import ghostWriter

struct AppLaunchBehaviorTests {
    @Test func launchActionCanBeginOnlyOnce() {
        var gate = AppLaunchActionGate()
        let firstAttempt = gate.begin()
        let secondAttempt = gate.begin()

        #expect(firstAttempt)
        #expect(!secondAttempt)
        #expect(gate.hasPerformed)
    }

    @Test func everyLaunchBehaviorHasAReadableLabel() {
        #expect(
            AppLaunchBehavior.allCases.map(\.label) == [
                "Show Library",
                "Start a New Document",
                "Open Last Document"
            ]
        )
    }
}
