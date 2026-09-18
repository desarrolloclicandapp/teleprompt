import XCTest

final class MonetizationScreenshotTests: XCTestCase {
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
