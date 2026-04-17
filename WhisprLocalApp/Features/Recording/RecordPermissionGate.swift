import Foundation

/// Holds the microphone permission state for `RecordView`.
///
/// Exists so the view can re-read the *live* system permission whenever the
/// scene returns to `.active`, rather than trapping a stale value in
/// `@State`. Without this refresh a user who denies the mic, taps "Open
/// Settings", grants the mic, and returns to the app would stay stuck on
/// `.denied` until relaunch — `beginRecording()`'s guard would fail
/// silently and lock them out. (Bugbot M1 finding, high severity.)
///
/// Keeping the logic in its own `@Observable` means the refresh contract
/// is unit-testable without a live SwiftUI scene lifecycle.
@Observable
@MainActor
final class RecordPermissionGate {

    private(set) var status: RecordingPermissionStatus
    private let authority: RecordingPermissionAuthority

    init(authority: RecordingPermissionAuthority) {
        self.authority = authority
        self.status = authority.currentStatus
    }

    /// Re-read the current system permission. Call on scene `.active`.
    func refreshFromSystem() {
        status = authority.currentStatus
    }

    /// If we've never asked, prompt. Otherwise no-op. Returns the resulting
    /// status so callers can branch without re-reading `status`.
    @discardableResult
    func requestIfNeeded() async -> RecordingPermissionStatus {
        if status == .notDetermined {
            status = await authority.request()
        }
        return status
    }
}
