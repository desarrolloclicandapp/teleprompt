import Foundation
import StoreKit
import StoreKitTest
import XCTest
@testable import Teleprompt

@MainActor
final class StoreKitConfigurationTests: XCTestCase {
    func testLocalStoreKitConfigurationExposesBothProducts() async throws {
        let bundle = Bundle(for: StoreKitConfigurationTests.self)
        let configurationURL = try XCTUnwrap(
            bundle.url(forResource: "Teleprompt", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        defer { withExtendedLifetime(session) {} }

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
}
