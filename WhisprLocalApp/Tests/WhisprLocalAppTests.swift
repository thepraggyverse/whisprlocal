import XCTest
@testable import WhisprLocalApp

/// M0 smoke test. Proves the test bundle loads, the app module links, and
/// CI can execute `xcodebuild test`. Real unit tests arrive milestone-by-
/// milestone alongside the code they cover.
final class WhisprLocalAppSmokeTests: XCTestCase {

    func testAppModuleLoads() {
        // If the `@testable import WhisprLocalApp` line compiles and this
        // test runs, the build graph is healthy — test target links against
        // the app target, WhisprShared resolves transitively, and the
        // simulator executed our code.
        XCTAssertTrue(true, "Smoke test placeholder until M1 lands real tests")
    }
}
