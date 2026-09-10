import Foundation

nonisolated struct CompilationExportSettings: Sendable {
    var usesSmartPunctuation = false
    var format = CompilationFormat.word
    var word = WordExportOptions()
    var powerPointTheme = PowerPointTheme.warmPaper
    var powerPointFont = PowerPointFont.arial
    var headingChoices: [CompilationFormat: Bool] = [:]
    var pageChoices: [CompilationFormat: Bool] = [:]
    var preservesHeadings: Bool {
        get { format == .word ? word.preservesHeadingStructure : headingChoices[format] ?? true }
        set { if format == .word { word.preservesHeadingStructure = newValue } else { headingChoices[format] = newValue } }
    }
    var startsOnNewPages: Bool {
        get { format == .word ? word.startsDocumentsOnNewPages : pageChoices[format] ?? true }
        set { if format == .word { word.startsDocumentsOnNewPages = newValue } else { pageChoices[format] = newValue } }
    }
    var brfCustomLayout = false
    var eBraille = EBrailleMetadata()
    var brfGrade = BrailleGrade.grade2
    var brfCells = 40
    var brfLines = 25
    var brfPurpose = BRFWriter.OutputPurpose.brailleDisplay
    var brfPageNumbers = true
}

