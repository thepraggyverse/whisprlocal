import XCTest

/// UI smoke tests. Asserts the app launches and the M1 record screen
/// renders the brand badge + the record button with its expected
/// accessibility label.
///
/// We rely on accessibility identifiers (via SwiftUI's automatic labels
/// and our explicit labels) so the test survives visual refactors.
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

    func testBrandBadgeVisible() throws {
        let app = XCUIApplication()
        app.launch()

        // Custom VoiceOver label from RecordView's brand badge.
        XCTAssertTrue(
            app.staticTexts["Runs 100 percent on device"].waitForExistence(timeout: 5),
            "Brand 'on-device' badge is missing from the record screen"
        )
    }

    func testRecordButtonAccessible() throws {
        let app = XCUIApplication()
        app.launch()

        // RecordButton accessibility label in idle state.
        let startButton = app.buttons["Start recording"]
        XCTAssertTrue(
            startButton.waitForExistence(timeout: 5),
            "'Start recording' button was not found on the record screen"
        )
        XCTAssertTrue(startButton.isEnabled)
    }
}
