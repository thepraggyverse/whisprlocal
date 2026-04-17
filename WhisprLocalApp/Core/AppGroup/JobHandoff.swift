import Foundation
import WhisprShared

/// Pure function that implements the IPC handoff step of spec §2: once a
/// WAV has been finalized inside App Group `inbox/`, write a `{uuid}.json`
/// envelope alongside it and post `DarwinNotificationNames.jobQueued` so
/// the main app's `InboxJobWatcher` picks up the pair.
///
/// Lives outside `AudioCaptureService` so both M2 (main-app recorder) and
/// M4 (keyboard extension recorder) can share the same contract without
/// the service-level ceremony. Tests exercise this directly with a spy
/// `DarwinNotificationCenter` — no AVAudioEngine needed.
enum JobHandoff {

    enum HandoffError: Error, Equatable {
        case wavFilenameNotAUUID(String)
    }

    /// Writes `{uuid}.json` alongside the given WAV and posts the
    /// `jobQueued` notification.
    ///
    /// - Parameters:
    ///   - wavURL: Finalized WAV at `inbox/{uuid}.wav`.
    ///   - createdAt: Timestamp to embed in the envelope.
    ///   - sourceBundleId: Best-effort source identifier. Main app passes
    ///     its own bundle ID; keyboard extension passes the host app's ID
    ///     when resolvable, else `nil`.
    ///   - pipeline: Pipeline preset. M2 always writes `"default"`; M3+
    ///     may set `"email"`, `"message"`, etc.
    ///   - notificationCenter: Injected so tests can spy on the post.
    static func writeEnvelopeAndPostJobQueued(
        forWAV wavURL: URL,
        createdAt: Date,
        sourceBundleId: String?,
        pipeline: String,
        notificationCenter: DarwinNotificationCenter
    ) throws {
        let stem = wavURL.deletingPathExtension().lastPathComponent
        guard let jobId = UUID(uuidString: stem) else {
            throw HandoffError.wavFilenameNotAUUID(stem)
        }

        let envelope = JobEnvelope(
            jobId: jobId,
            createdAt: createdAt,
            sourceBundleId: sourceBundleId,
            pipeline: pipeline
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let envelopeURL = wavURL.deletingPathExtension().appendingPathExtension("json")
        try data.write(to: envelopeURL, options: [.atomic, .completeFileProtection])

        notificationCenter.post(DarwinNotificationNames.jobQueued)
    }
}
