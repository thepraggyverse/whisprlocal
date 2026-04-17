import Foundation

/// Canonical paths inside the App Group shared container used for IPC between
/// the main app and the keyboard extension.
///
/// - `inbox/`  — keyboard writes `{jobId}.wav` + `{jobId}.json` here.
/// - `outbox/` — main app writes `{jobId}.txt` (polished text) here.
///
/// Do not rename the identifier or the subdirectory names without updating
/// the keyboard target's entitlements and the Darwin notification names.
public enum AppGroupPaths {

    /// App Group identifier. Must match the entitlements on both targets.
    public static let identifier = "group.com.praggy.whisprlocal"

    /// Shared container root for this App Group, or `nil` if the entitlement
    /// is missing (common in unit tests or when Full Access is not granted).
    public static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }

    /// `inbox/` — pending jobs written by the keyboard, read by the main app.
    public static var inboxURL: URL? {
        containerURL?.appendingPathComponent("inbox", isDirectory: true)
    }

    /// `outbox/` — completed transcriptions written by the main app, read by
    /// the keyboard for insertion via `UITextDocumentProxy`.
    public static var outboxURL: URL? {
        containerURL?.appendingPathComponent("outbox", isDirectory: true)
    }
}
