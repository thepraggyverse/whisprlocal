import Foundation
import notify

/// Thin wrapper around the `notify(3)` C API so the publisher
/// (`AudioCaptureService`) and the observer (`InboxJobWatcher`) share a
/// single testable seam. Tests can inject an in-memory fake and drive
/// callbacks synchronously without touching the kernel.
///
/// Darwin notifications are process-global strings — the name contract
/// lives in `WhisprShared.DarwinNotificationNames` so both the main app
/// and (at M4) the keyboard extension match on identical constants.
protocol DarwinNotificationCenter: Sendable {

    /// Post a notification for all observers of `name` across every
    /// process on the device.
    func post(_ name: String)

    /// Register a callback for `name`. The callback runs on `queue` on
    /// every notification. Returns a token; pass it to `cancel` to
    /// unregister. Callers must retain the token for the duration of
    /// observation — dropping it on the floor leaks the underlying
    /// notify(3) registration.
    func register(
        _ name: String,
        queue: DispatchQueue,
        callback: @escaping @Sendable () -> Void
    ) -> Int32

    /// Unregister a previously returned token. Safe to call with
    /// `NOTIFY_STATUS_INVALID_TOKEN` (`-1`) — becomes a no-op.
    func cancel(_ token: Int32)
}

/// Production `DarwinNotificationCenter` backed by the kernel's
/// `notify_post` / `notify_register_dispatch` APIs.
struct SystemDarwinNotificationCenter: DarwinNotificationCenter {

    func post(_ name: String) {
        notify_post(name)
    }

    func register(
        _ name: String,
        queue: DispatchQueue,
        callback: @escaping @Sendable () -> Void
    ) -> Int32 {
        var token: Int32 = -1
        let status = notify_register_dispatch(name, &token, queue) { _ in
            callback()
        }
        guard status == NOTIFY_STATUS_OK else {
            // notify(3) rejected the registration — return the invalid
            // sentinel so callers can detect and skip cancel().
            return -1
        }
        return token
    }

    func cancel(_ token: Int32) {
        guard token != -1 else { return }
        notify_cancel(token)
    }
}
