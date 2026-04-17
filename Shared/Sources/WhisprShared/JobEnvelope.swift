import Foundation

/// Metadata envelope paired with each `{jobId}.wav` in the App Group `inbox/`.
///
/// Written by the keyboard extension, consumed by the main app's transcription
/// pipeline. Stable Codable shape — renames here are an IPC-breaking change.
public struct JobEnvelope: Codable, Sendable, Equatable {

    /// Unique identifier. Used to pair the WAV, this envelope, and the
    /// corresponding `outbox/{jobId}.txt` result.
    public let jobId: UUID

    /// When the keyboard finished recording, in the device's local time.
    public let createdAt: Date

    /// Best-effort source bundle identifier (the app the keyboard was active
    /// in when the user tapped record). `nil` when unavailable — the keyboard
    /// can't always resolve this for sandbox/privacy reasons.
    public let sourceBundleId: String?

    /// Pipeline preset selected by the user (e.g. "default", "email",
    /// "message", "code_comment"). Resolved server-side (main app) to a
    /// specific prompt template from `PolishEngine`.
    public let pipeline: String

    public init(
        jobId: UUID = UUID(),
        createdAt: Date = Date(),
        sourceBundleId: String? = nil,
        pipeline: String = "default"
    ) {
        self.jobId = jobId
        self.createdAt = createdAt
        self.sourceBundleId = sourceBundleId
        self.pipeline = pipeline
    }
}
