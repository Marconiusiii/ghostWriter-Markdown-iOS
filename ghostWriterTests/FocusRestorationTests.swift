//
//  FocusRestorationTests.swift
//  ghostWriterTests
//

import Testing
@testable import ghostWriter

struct FocusRestorationTests {

    @Test func onlyNewestFocusRequestIsPermitted() {
        var gate = FocusRestorationRequestGate()

        let first = gate.begin()
        let second = gate.begin()

        #expect(!gate.permits(first))
        #expect(gate.permits(second))
    }

    @Test func invalidationRejectsPendingRequest() {
        var gate = FocusRestorationRequestGate()

        let request = gate.begin()
        gate.invalidate()

        #expect(!gate.permits(request))
    }
}
