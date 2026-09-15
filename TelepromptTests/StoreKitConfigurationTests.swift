import Foundation
import StoreKit
import StoreKitTest
import XCTest
@testable import Teleprompt

@MainActor
final class StoreKitConfigurationTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        let bundle = Bundle(for: StoreKitConfigurationTests.self)
        let configurationURL = try XCTUnwrap(
            bundle.url(forResource: "Teleprompt", withExtension: "storekit")
        )
        session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        try session.clearTransactions()
    }

    override func tearDownWithError() throws {
        try session?.clearTransactions()
        session = nil
    }

    func testLocalStoreKitConfigurationExposesBothProducts() async throws {
        let products = try await Product.products(for: StoreKitConfiguration.productIDs)
        let trial = try XCTUnwrap(
            products.first(where: { $0.id == StoreKitConfiguration.trialProductID })
        )
        let lifetime = try XCTUnwrap(
            products.first(where: { $0.id == StoreKitConfiguration.lifetimeProductID })
        )

        XCTAssertEqual(Set(products.map(\.id)), Set(StoreKitConfiguration.productIDs))
        XCTAssertEqual(trial.type, .nonConsumable)
        XCTAssertEqual(trial.price, .zero)
        XCTAssertEqual(lifetime.type, .nonConsumable)
        XCTAssertGreaterThan(lifetime.price, .zero)
    }

    func testLifetimeProductCreatesAPersistedStoreKitEntitlement() async throws {
        try session.buyProduct(identifier: StoreKitConfiguration.lifetimeProductID)

        let purchases = session.allTransactions()
        XCTAssertEqual(purchases.count, 1)
        XCTAssertEqual(purchases.first?.productIdentifier, StoreKitConfiguration.lifetimeProductID)
        let entitlementIDs = await currentEntitlementIDs()
        XCTAssertTrue(entitlementIDs.contains(StoreKitConfiguration.lifetimeProductID))
    }

    func testRefundedLifetimeIsNoLongerAnEntitlement() async throws {
        try session.buyProduct(identifier: StoreKitConfiguration.lifetimeProductID)
        let transaction = try XCTUnwrap(session.allTransactions().first)

        try session.refundTransaction(identifier: transaction.identifier)

        let entitlementIDs = await currentEntitlementIDs()
        XCTAssertFalse(entitlementIDs.contains(StoreKitConfiguration.lifetimeProductID))
    }

    private func currentEntitlementIDs() async -> Set<String> {
        var productIDs = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                productIDs.insert(transaction.productID)
            }
        }
        return productIDs
    }
}
