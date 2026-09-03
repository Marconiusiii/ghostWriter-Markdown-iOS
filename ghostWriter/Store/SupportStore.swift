//
//  SupportStore.swift
//  ghostWriter
//
//  Loads and purchases the optional consumable support products. A verified
//  transaction records only the latest support name and date on this device.
//

import Foundation
import Observation
import StoreKit

@Observable
final class SupportStore {
    enum SupportStatus: Equatable, Sendable {
        case idle
        case loading
        case purchasing(String)
        case success(SupportThankYou)
        case pending
        case productLoadFailed
        case purchaseFailed
        case verificationFailed
        case unexpected
    }

    struct SupportOption: Identifiable, Equatable, Sendable {
        let productID: String
        let fallbackName: String

        var id: String { productID }
    }

    struct SupportThankYou: Equatable, Sendable {
        let productID: String
        let supportName: String
        let date: Date
    }

    static let supportOptions: [SupportOption] = [
        SupportOption(
            productID: "com.marconius.ghostwriter.support.littleBoooo",
            fallbackName: "Little Boo"
        ),
        SupportOption(
            productID: "com.marconius.ghostwriter.support.bigBoo",
            fallbackName: "Big Boo"
        ),
        SupportOption(
            productID: "com.marconius.ghostwriter.support.spookyWail",
            fallbackName: "Spooky Wail"
        ),
        SupportOption(
            productID: "com.marconius.ghostwriter.support.startlingScream",
            fallbackName: "Startling Scream"
        )
    ]

    private(set) var products: [Product] = []
    private(set) var status: SupportStatus = .idle
    private(set) var latestThankYou: SupportThankYou?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let displaysScreenshotProducts: Bool
    @ObservationIgnored private var transactionListener: Task<Void, Never>?

    private enum StorageKey {
        static let productID = "ghostWriter.support.latestProductID"
        static let supportDate = "ghostWriter.support.latestDate"
        static let transactionID = "ghostWriter.support.latestTransactionID"
    }

    init(
        defaults: UserDefaults = .standard,
        listensForTransactions: Bool = true
    ) {
        self.defaults = defaults
        displaysScreenshotProducts = Self.screenshotModeWasRequested
        latestThankYou = Self.storedThankYou(in: defaults)

        if listensForTransactions {
            transactionListener = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    await self.processUpdatedTransaction(result)
                }
            }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
#if DEBUG
        if displaysScreenshotProducts {
            status = .idle
            return
        }
#endif

        status = .loading

        do {
            let identifiers = Self.supportOptions.map(\.productID)
            let loadedProducts = try await Product.products(for: identifiers)
            products = loadedProducts.sorted {
                Self.optionIndex(for: $0.id) < Self.optionIndex(for: $1.id)
            }
            status = products.count == Self.supportOptions.count
                ? .idle
                : .productLoadFailed
        } catch {
            products = []
            status = .productLoadFailed
        }
    }

    func product(for option: SupportOption) -> Product? {
        products.first { $0.id == option.productID }
    }

    func isAvailable(_ option: SupportOption) -> Bool {
#if DEBUG
        if displaysScreenshotProducts {
            return true
        }
#endif
        return product(for: option) != nil
    }

    func displayPrice(for option: SupportOption) -> String? {
#if DEBUG
        if displaysScreenshotProducts {
            return Self.screenshotPrices[option.productID]
        }
#endif
        return product(for: option)?.displayPrice
    }

    func purchase(_ option: SupportOption) async {
#if DEBUG
        if displaysScreenshotProducts {
            guard let thankYou = recordSuccessfulSupport(
                productID: option.productID,
                purchaseDate: .now,
                transactionID: "screenshot-\(UUID().uuidString)"
            ) else {
                status = .unexpected
                return
            }
            status = .success(thankYou)
            return
        }
#endif

        guard let product = product(for: option) else {
            status = .productLoadFailed
            return
        }

        status = .purchasing(displayName(for: option))

        do {
            switch try await product.purchase() {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    guard let thankYou = recordSuccessfulSupport(
                        productID: transaction.productID,
                        purchaseDate: transaction.purchaseDate,
                        transactionID: String(transaction.id)
                    ) else {
                        status = .unexpected
                        return
                    }
                    await transaction.finish()
                    status = .success(thankYou)
                case .unverified:
                    status = .verificationFailed
                }
            case .pending:
                status = .pending
            case .userCancelled:
                status = .idle
            @unknown default:
                status = .unexpected
            }
        } catch {
            status = .purchaseFailed
        }
    }

    func displayName(for option: SupportOption) -> String {
        guard let storeName = product(for: option)?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !storeName.isEmpty
        else {
            return option.fallbackName
        }
        return storeName
    }

    var isPurchasing: Bool {
        if case .purchasing = status { return true }
        return false
    }

    @discardableResult
    func recordSuccessfulSupport(
        productID: String,
        purchaseDate: Date,
        transactionID: String
    ) -> SupportThankYou? {
        guard let option = Self.supportOptions.first(where: {
            $0.productID == productID
        }) else {
            return nil
        }

        let thankYou = SupportThankYou(
            productID: productID,
            supportName: displayName(for: option),
            date: purchaseDate
        )
        defaults.set(productID, forKey: StorageKey.productID)
        defaults.set(purchaseDate, forKey: StorageKey.supportDate)
        defaults.set(transactionID, forKey: StorageKey.transactionID)
        latestThankYou = thankYou
        return thankYou
    }

    private func processUpdatedTransaction(
        _ result: VerificationResult<Transaction>
    ) async {
        switch result {
        case .verified(let transaction):
            guard Self.supportOptions.contains(where: {
                $0.productID == transaction.productID
            }) else {
                return
            }

            if defaults.string(forKey: StorageKey.transactionID)
                == String(transaction.id) {
                await transaction.finish()
                return
            }

            guard let thankYou = recordSuccessfulSupport(
                productID: transaction.productID,
                purchaseDate: transaction.purchaseDate,
                transactionID: String(transaction.id)
            ) else {
                status = .unexpected
                return
            }
            await transaction.finish()
            status = .success(thankYou)
        case .unverified:
            status = .verificationFailed
        }
    }

    private static func storedThankYou(
        in defaults: UserDefaults
    ) -> SupportThankYou? {
        guard
            let productID = defaults.string(forKey: StorageKey.productID),
            let option = supportOptions.first(where: {
                $0.productID == productID
            }),
            let date = defaults.object(forKey: StorageKey.supportDate) as? Date
        else {
            return nil
        }

        return SupportThankYou(
            productID: productID,
            supportName: option.fallbackName,
            date: date
        )
    }

    private static func optionIndex(for productID: String) -> Int {
        supportOptions.firstIndex { $0.productID == productID } ?? Int.max
    }

    private static var screenshotModeWasRequested: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-supportScreenshotMode")
#else
        false
#endif
    }

#if DEBUG
    private static let screenshotPrices = [
        "com.marconius.ghostwriter.support.littleBoooo": "$0.99",
        "com.marconius.ghostwriter.support.bigBoo": "$1.99",
        "com.marconius.ghostwriter.support.spookyWail": "$2.99",
        "com.marconius.ghostwriter.support.startlingScream": "$4.99"
    ]
#endif
}
