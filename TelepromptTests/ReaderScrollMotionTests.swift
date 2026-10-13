import XCTest
@testable import Teleprompt

final class ReaderScrollMotionTests: XCTestCase {
    func testAutomaticScrollDistanceIsIndependentOfFrameRate() {
        let oneSixtieth = ReaderScrollMotion.automaticDistance(
            speed: 1_200,
            fontScale: 1,
            elapsed: 1.0 / 60.0
        )
        let twoOneTwentieths = ReaderScrollMotion.automaticDistance(
            speed: 1_200,
            fontScale: 1,
            elapsed: 1.0 / 120.0
        ) * 2

        XCTAssertEqual(oneSixtieth, twoOneTwentieths, accuracy: 0.000_1)
    }

    func testJoystickCanMoveBackTowardsTheBeginning() {
        let distance = ReaderScrollMotion.joystickDistance(
            input: -1,
            speed: 600,
            fontScale: 1,
            elapsed: 1.0 / 60.0
        )

        XCTAssertLessThan(distance, 0)
    }

    func testInvalidElapsedTimeDoesNotMoveTheScript() {
        XCTAssertEqual(
            ReaderScrollMotion.automaticDistance(
                speed: 600,
                fontScale: 1,
                elapsed: -.infinity
            ),
            0
        )
    }
}
