//
//  LineStructureTests.swift
//  ghostWriterTests
//
//  The spoken descriptions produced here are what a writer hears as they move
//  the cursor, so the classification needs to be right.
//

import Testing
@testable import ghostWriter

struct LineStructureTests {

    @Test func detectsHeadingLevels() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let structure = LineAnalyzer.analyze("\(hashes) Title")
            #expect(structure.kind == .heading(level: level))
        }
    }

    /// Seven hashes is not a heading in markdown.
    @Test func rejectsTooManyHashes() {
        #expect(LineAnalyzer.analyze("####### Title").kind == .paragraph)
    }

    /// A hash with no following space is a paragraph, not a heading.
    @Test func requiresSpaceAfterHashes() {
        #expect(LineAnalyzer.analyze("#NotAHeading").kind == .paragraph)
    }

    @Test func detectsBlankLine() {
        #expect(LineAnalyzer.analyze("").kind == .blank)
        #expect(LineAnalyzer.analyze("   ").kind == .blank)
    }

    @Test func detectsUnorderedItems() {
        #expect(LineAnalyzer.analyze("- Item").kind == .unorderedItem(depth: 0))
        #expect(LineAnalyzer.analyze("  - Item").kind == .unorderedItem(depth: 1))
    }

    @Test func detectsOrderedItems() {
        #expect(LineAnalyzer.analyze("1. Item").kind == .orderedItem(number: 1, depth: 0))
        #expect(LineAnalyzer.analyze("  7. Item").kind == .orderedItem(number: 7, depth: 1))
    }

    @Test func detectsBlockquoteDepth() {
        #expect(LineAnalyzer.analyze("> Quote").kind == .blockquote(depth: 1))
        #expect(LineAnalyzer.analyze(">> Nested").kind == .blockquote(depth: 2))
    }

    @Test func detectsHorizontalRules() {
        #expect(LineAnalyzer.analyze("---").kind == .horizontalRule)
        #expect(LineAnalyzer.analyze("***").kind == .horizontalRule)
        #expect(LineAnalyzer.analyze("- - -").kind == .horizontalRule)
    }

    /// Two dashes is not a rule.
    @Test func rejectsShortRules() {
        #expect(LineAnalyzer.analyze("--").kind != .horizontalRule)
    }

    @Test func detectsCodeFence() {
        #expect(LineAnalyzer.analyze("```").kind == .codeFence)
        #expect(LineAnalyzer.analyze("```swift").kind == .codeFence)
    }

    /// Inside a fence, markdown syntax is literal text and must not be parsed.
    @Test func treatsFencedContentAsCode() {
        let structure = LineAnalyzer.analyze("# Not a heading", insideCodeBlock: true)
        #expect(structure.kind == .codeContent)
    }

    @Test func detectsTableRowsAndDividers() {
        #expect(LineAnalyzer.analyze("| A | B |").kind == .tableRow)
        #expect(LineAnalyzer.analyze("| --- | --- |").kind == .tableDivider)
        #expect(LineAnalyzer.analyze("| :-- | --: |").kind == .tableDivider)
    }

    @Test func countsTabsAsTwoColumns() {
        #expect(LineAnalyzer.indentColumns(of: "\tx") == 2)
        #expect(LineAnalyzer.indentColumns(of: "    x") == 4)
    }

    @Test func tracksCodeBlockMembership() {
        let lines = ["Intro", "```", "code", "```", "After"]
        #expect(LineAnalyzer.isInsideCodeBlock(lines: lines, lineIndex: 0) == false)
        #expect(LineAnalyzer.isInsideCodeBlock(lines: lines, lineIndex: 2) == true)
        #expect(LineAnalyzer.isInsideCodeBlock(lines: lines, lineIndex: 4) == false)
    }

    // MARK: - Spoken descriptions

    @Test func speaksHeadingLevel() {
        #expect(LineAnalyzer.analyze("## Title").spokenDescription == "Heading level 2")
    }

    @Test func speaksNestingDepth() {
        #expect(LineAnalyzer.analyze("- Item").spokenDescription == "Bullet")
        #expect(LineAnalyzer.analyze("  - Item").spokenDescription == "Bullet, level 2")
    }

    @Test func speaksOrderedItemNumber() {
        #expect(LineAnalyzer.analyze("3. Item").spokenDescription == "Item 3")
    }
}
