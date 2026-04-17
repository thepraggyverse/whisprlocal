import Foundation

/// Darwin notification names used for cross-process signaling between the
/// main app and the keyboard extension.
///
/// Renaming any constant here silently breaks the keyboard↔app handoff
/// because the subscriber and publisher live in different processes and
/// match on string equality. Treat this as a stable API.
public enum DarwinNotificationNames {

    /// Posted by the keyboard after writing a new `{jobId}.wav` + envelope
    /// to `inbox/`. The main app observes this and begins processing.
    public static let jobQueued = "com.praggy.whisprlocal.job.queued"

    /// Posted by the main app after writing `{jobId}.txt` to `outbox/`.
    /// The keyboard observes this and inserts the text via `textDocumentProxy`.
    public static let jobDone = "com.praggy.whisprlocal.job.done"
}
