import XCTest
import StoreKitTest

final class MonetizationScreenshotTests: XCTestCase {
    private var storeKitSession: SKTestSession?

    override func setUpWithError() throws {
        continueAfterFailure = false

        let bundle = Bundle(for: Self.self)
        let configurationURL = try XCTUnwrap(
            bundle.url(forResource: "Teleprompt", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        storeKitSession = session
    }

    override func tearDown() {
        storeKitSession = nil
        super.tearDown()
    }

    func testCaptureInitialPurchaseScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-teleprompt.resetLocalMonetization"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["trial.lifetime_price"].waitForExistence(timeout: 15),
            "The lifetime price should be visible before capturing the purchase screen."
        )

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "initial-purchase-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
