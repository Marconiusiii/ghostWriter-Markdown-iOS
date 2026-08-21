import Testing
@testable import ghostWriter

struct DocumentLanguageTests {
    @Test func normalizesCommonBCP47Forms() {
        #expect(DocumentLanguage.normalizedTag("es_mx") == "es-MX")
        #expect(DocumentLanguage.normalizedTag("zh-hans-cn") == "zh-Hans-CN")
        #expect(DocumentLanguage.normalizedTag(" English ").isEmpty)
    }

    @Test func SpanishDocumentsSuggestUncontractedSpanishBraille() {
        #expect(BrailleGrade.suggested(for: "es", englishDefault: .grade2) == .spanishGrade1)
        #expect(BrailleGrade.suggested(for: "es-AR", englishDefault: .grade2) == .spanishGrade1)
        #expect(BrailleGrade.suggested(for: "en-GB", englishDefault: .grade1) == .grade1)
    }

    @Test func brailleTagPreservesMatchingRegion() {
        #expect(BrailleLanguageTag.brailleTag(from: "es", regionFrom: "es-MX") == "es-Brai-MX")
        #expect(BrailleLanguageTag.brailleTag(from: "es", regionFrom: "en-US") == "es-Brai")
    }
}
