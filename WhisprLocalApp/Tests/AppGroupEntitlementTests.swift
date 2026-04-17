import XCTest
import WhisprShared

/// Guards the "error code 2" bug caught during M1 simulator verification:
/// if the Debug build config disables code signing (e.g. by setting
/// `CODE_SIGNING_ALLOWED: NO`), the `com.apple.security.application-groups`
/// entitlement is never embedded in the binary and every recording attempt
/// throws `AudioCaptureService.CaptureError.appGroupContainerMissing` at the
/// first call in `start()`.
///
/// The test runs inside the app host, so its resolution of
/// `AppGroupPaths.containerURL` is a faithful proxy for what the running
/// app will see at `record`-button tap time.
final class AppGroupEntitlementTests: XCTestCase {

    func testAppGroupContainerIsReachable() {
        XCTAssertNotNil(
            AppGroupPaths.containerURL,
            "group.com.praggy.whisprlocal container is nil — check that "
            + "CODE_SIGNING_ALLOWED is not NO in Debug, which would strip "
            + "the app-groups entitlement from the test host."
        )
    }

    func testInboxURLReachable() {
        XCTAssertNotNil(AppGroupPaths.inboxURL)
    }
}
