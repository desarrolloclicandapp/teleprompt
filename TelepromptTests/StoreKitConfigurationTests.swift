import Foundation
import StoreKit
import StoreKitTest
import XCTest
@testable import Teleprompt

@MainActor
final class StoreKitConfigurationTests: XCTestCase {
    func testLocalStoreKitConfigurationExposesLifetimeUnlock() async throws {
        let bundle = Bundle(for: StoreKitConfigurationTests.self)
        let configurationURL = try XCTUnwrap(
            bundle.url(forResource: "Teleprompt", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        defer { withExtendedLifetime(session) {} }
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        let products = try await Product.products(for: StoreKitConfiguration.productIDs)
        let lifetime = try XCTUnwrap(
            products.first(where: { $0.id == StoreKitConfiguration.lifetimeProductID })
        )

        XCTAssertEqual(Set(products.map(\.id)), Set(StoreKitConfiguration.productIDs))
        XCTAssertEqual(lifetime.type, .nonConsumable)
        XCTAssertGreaterThan(lifetime.price, .zero)
    }
}
