import XCTest
@testable import WhisprLocalApp

/// Regression guard for Bugbot M1 finding #1 (high severity): `RecordView`
/// used to cache `permissionStatus` once from `.task(id:)` and never
/// refresh it. If the user denied the mic, tapped "Open Settings",
/// flipped the toggle on, and returned to the app, the cached state
/// stayed `.denied` — `beginRecording()`'s guard failed silently and the
/// user was locked out of recording until relaunch.
///
/// The fix moves the permission state into `RecordPermissionGate` and
/// refreshes it on `scenePhase == .active`. These tests exercise the gate
/// end-to-end with a mutable stub authority that mimics the
/// Settings-grant round trip.
@MainActor
final class RecordPermissionGateTests: XCTestCase {

    func testRefreshPicksUpGrantAfterSettingsRoundTrip() async {
        let stub = MutableStubAuthority(currentStatus: .denied, requestResult: .denied)
        let gate = RecordPermissionGate(authority: stub)

        XCTAssertEqual(gate.status, .denied, "Gate should start by reading the authority's current status.")

        // Simulate: user taps "Open Settings", flips mic permission on in
        // iOS Settings, returns to the app. The authority now reports
        // .granted, but nothing has told the gate yet.
        stub.currentStatus = .granted
        XCTAssertEqual(gate.status, .denied, "Without a refresh, the gate must still reflect the stale cache — that *is* the bug.")

        // SwiftUI's .onChange(of: scenePhase) .active handler calls this.
        gate.refreshFromSystem()

        XCTAssertEqual(
            gate.status,
            .granted,
            "After scene returns to .active, gate must pick up the live system permission — otherwise the user stays locked out."
        )

        // The recording path guards on gate.requestIfNeeded() — when the
        // status is already .granted it must short-circuit past any
        // further prompt and return .granted so beginRecording() proceeds.
        let resolved = await gate.requestIfNeeded()
        XCTAssertEqual(resolved, .granted)
        XCTAssertEqual(stub.requestCallCount, 0, "Must not re-prompt when the live status is already resolved.")
    }

    func testRequestIfNeededPromptsOnlyWhenNotDetermined() async {
        let stub = MutableStubAuthority(currentStatus: .notDetermined, requestResult: .granted)
        let gate = RecordPermissionGate(authority: stub)

        let first = await gate.requestIfNeeded()
        XCTAssertEqual(first, .granted)
        XCTAssertEqual(stub.requestCallCount, 1)

        let second = await gate.requestIfNeeded()
        XCTAssertEqual(second, .granted)
        XCTAssertEqual(stub.requestCallCount, 1, "Second call must not re-prompt the user.")
    }

    func testRefreshFlipsStatusEveryCall() {
        let stub = MutableStubAuthority(currentStatus: .notDetermined, requestResult: .granted)
        let gate = RecordPermissionGate(authority: stub)

        stub.currentStatus = .granted
        gate.refreshFromSystem()
        XCTAssertEqual(gate.status, .granted)

        stub.currentStatus = .denied
        gate.refreshFromSystem()
        XCTAssertEqual(gate.status, .denied, "If the user toggled the permission off mid-session, the refresh must still see it.")
    }

    // MARK: - Stub

    /// Class-based stub so the test can mutate `currentStatus` between
    /// reads — emulating the user's trip through iOS Settings.
    private final class MutableStubAuthority: RecordingPermissionAuthority, @unchecked Sendable {
        var currentStatus: RecordingPermissionStatus
        var requestResult: RecordingPermissionStatus
        private(set) var requestCallCount = 0

        init(currentStatus: RecordingPermissionStatus, requestResult: RecordingPermissionStatus) {
            self.currentStatus = currentStatus
            self.requestResult = requestResult
        }

        func request() async -> RecordingPermissionStatus {
            requestCallCount += 1
            return requestResult
        }
    }
}
