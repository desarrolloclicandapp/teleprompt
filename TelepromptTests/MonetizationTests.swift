import XCTest
@testable import Teleprompt

final class MonetizationTests: XCTestCase {
    func testTrialLastsExactlySevenDays() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(StoreKitConfiguration.trialDuration)

        XCTAssertEqual(
            TrialClock.endDate(for: start),
            end
        )
        XCTAssertTrue(
            TrialClock.state(startDate: start, now: end.addingTimeInterval(-1))
                .isActiveTrial
        )
        XCTAssertEqual(
            TrialClock.state(startDate: start, now: end),
            .trialExpired
        )
        XCTAssertEqual(TrialClock.remainingDays(startDate: start, now: start), 7)
        XCTAssertEqual(
            TrialClock.remainingDays(startDate: start, now: end.addingTimeInterval(-1)),
            1
        )
        XCTAssertEqual(TrialClock.remainingDays(startDate: start, now: end), 0)
    }

    func testNoTrialHasNotStarted() {
        XCTAssertEqual(TrialClock.state(startDate: nil, now: .now), .trialNotStarted)
    }

    func testLegacyVersionComparison() {
        XCTAssertTrue(StoreKitConfiguration.isVersion("1.0.1", atMost: "1.0.1"))
        XCTAssertTrue(StoreKitConfiguration.isVersion("1.0.0", atMost: "1.0.1"))
        XCTAssertFalse(StoreKitConfiguration.isVersion("1.1.0", atMost: "1.0.1"))
        XCTAssertFalse(StoreKitConfiguration.isVersion("1785247605", atMost: "1.0.1"))
        XCTAssertFalse(StoreKitConfiguration.isVersion("1.beta", atMost: "1.0.1"))
        XCTAssertFalse(StoreKitConfiguration.isVersion("1.0.", atMost: "1.0.1"))
        XCTAssertFalse(StoreKitConfiguration.isVersion("-1.0", atMost: "1.0.1"))
    }

    func testPurchaseFlowBlocksOnlyWhenAppropriate() {
        XCTAssertFalse(PurchaseFlowState.idle.isBusy)
        XCTAssertFalse(PurchaseFlowState.idle.blocksPurchase)
        XCTAssertTrue(PurchaseFlowState.purchasing.isBusy)
        XCTAssertTrue(PurchaseFlowState.purchasing.blocksPurchase)
        XCTAssertTrue(PurchaseFlowState.restoring.isBusy)
        XCTAssertTrue(PurchaseFlowState.pending.blocksPurchase)
        XCTAssertFalse(PurchaseFlowState.cancelled.blocksPurchase)
        XCTAssertFalse(PurchaseFlowState.failed("Error").blocksPurchase)
    }

    func testLifetimeUnlockIsTheOnlyAppStoreProduct() {
        XCTAssertEqual(
            Set(StoreKitConfiguration.productIDs),
            Set([StoreKitConfiguration.lifetimeProductID])
        )
        XCTAssertFalse(StoreKitConfiguration.lifetimeProductID.isEmpty)
    }
}

private extension MonetizationState {
    var isActiveTrial: Bool {
        if case .trialActive = self { return true }
        return false
    }
}
