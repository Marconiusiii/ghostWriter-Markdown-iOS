import Foundation
import Testing
@testable import ghostWriter

struct SupportStoreTests {
    @Test func supportOptionsUseTheApprovedOrderAndIdentifiers() {
        #expect(SupportStore.supportOptions.map(\.fallbackName) == [
            "Little Boo",
            "Big Boo",
            "Spooky Wail",
            "Startling Scream"
        ])
        #expect(SupportStore.supportOptions.map(\.productID) == [
            "com.marconius.ghostwriter.support.littleBoooo",
            "com.marconius.ghostwriter.support.bigBoo",
            "com.marconius.ghostwriter.support.spookyWail",
            "com.marconius.ghostwriter.support.startlingScream"
        ])
    }

    @Test func verifiedSupportHistoryPersistsTheProductAndPurchaseDate() {
        let suiteName = "ghostWriterSupportTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = Date(timeIntervalSince1970: 1_788_249_600)

        let store = SupportStore(
            defaults: defaults,
            listensForTransactions: false
        )
        let recorded = store.recordSuccessfulSupport(
            productID: SupportStore.supportOptions[2].productID,
            purchaseDate: date,
            transactionID: "42"
        )

        #expect(recorded?.supportName == "Spooky Wail")
        #expect(recorded?.date == date)

        let restored = SupportStore(
            defaults: defaults,
            listensForTransactions: false
        )
        #expect(restored.latestThankYou?.productID == recorded?.productID)
        #expect(restored.latestThankYou?.supportName == recorded?.supportName)
        #expect(restored.latestThankYou?.date == recorded?.date)
    }

    @Test func unknownProductsNeverCreateSupportHistory() {
        let suiteName = "ghostWriterSupportTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SupportStore(
            defaults: defaults,
            listensForTransactions: false
        )

        let recorded = store.recordSuccessfulSupport(
            productID: "not-a-support-product",
            purchaseDate: .now,
            transactionID: "43"
        )

        #expect(recorded == nil)
        #expect(store.latestThankYou == nil)
    }
}
