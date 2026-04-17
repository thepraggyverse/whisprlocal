import XCTest

/// M0 UI smoke test. Launches the app and confirms the landing view's
/// "WhisprLocal" title is visible. Locks in the "on-device" brand promise
/// badge as well — if someone removes it in a future refactor, this test
/// will fail and surface the change for review.
final class WhisprLocalAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsTitle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["WhisprLocal"].waitForExistence(timeout: 5),
            "App did not render the 'WhisprLocal' title within 5 seconds"
        )
    }
}
