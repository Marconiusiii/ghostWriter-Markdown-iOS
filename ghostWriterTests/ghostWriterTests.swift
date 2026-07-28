//
//  ghostWriterTests.swift
//  ghostWriterTests
//
//  Created by Marco Salsiccia on 7/27/26.
//

import Foundation
import Testing
@testable import ghostWriter

/// Smoke test that the app module is importable. The real coverage lives in the
/// focused test files alongside this one.
struct ghostWriterTests {

    @Test func documentRecognisesMarkdownExtensions() {
        #expect(Document.isMarkdown(URL(fileURLWithPath: "/tmp/note.md")))
        #expect(Document.isMarkdown(URL(fileURLWithPath: "/tmp/note.MD")))
        #expect(!Document.isMarkdown(URL(fileURLWithPath: "/tmp/image.png")))
    }
}
