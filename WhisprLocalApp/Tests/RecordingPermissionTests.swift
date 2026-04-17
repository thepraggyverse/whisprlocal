import AVFoundation
import XCTest
@testable import WhisprLocalApp

final class RecordingPermissionTests: XCTestCase {

    func testMapping() {
        XCTAssertEqual(
            AVRecordingPermissionAuthority.map(.undetermined),
            .notDetermined
        )
        XCTAssertEqual(
            AVRecordingPermissionAuthority.map(.denied),
            .denied
        )
        XCTAssertEqual(
            AVRecordingPermissionAuthority.map(.granted),
            .granted
        )
    }

    func testStubbedAuthorityReturnsStatusUnchangedByRequest() async {
        let stub = StubAuthority(initial: .granted, toReturn: .granted)
        XCTAssertEqual(stub.currentStatus, .granted)
        let result = await stub.request()
        XCTAssertEqual(result, .granted)
    }

    func testStubbedAuthorityRejectsOnDeny() async {
        let stub = StubAuthority(initial: .notDetermined, toReturn: .denied)
        XCTAssertEqual(stub.currentStatus, .notDetermined)
        let result = await stub.request()
        XCTAssertEqual(result, .denied)
    }

    // MARK: - Stub

    private struct StubAuthority: RecordingPermissionAuthority {
        let currentStatus: RecordingPermissionStatus
        let toReturn: RecordingPermissionStatus

        init(initial: RecordingPermissionStatus, toReturn: RecordingPermissionStatus) {
            self.currentStatus = initial
            self.toReturn = toReturn
        }

        func request() async -> RecordingPermissionStatus { toReturn }
    }
}
