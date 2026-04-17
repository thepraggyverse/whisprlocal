import Foundation

/// Abstract boundary around the speech-to-text engine. Production callers
/// depend on this protocol so they can be exercised in unit tests without
/// loading a ~75 MB model or touching WhisperKit.
///
/// The real implementation lives in `WhisperEngine`. `StubTranscriber`
/// provides a deterministic test/preview double.
protocol Transcriber: Sendable {

    /// Transcribe the WAV (or compatible audio) at `audioURL` using the
    /// model identified by `modelId` (a `ModelEntry.id`). Throws if the
    /// model is not in the catalog, not on disk, or the underlying engine
    /// returns no result.
    func transcribe(audioURL: URL, modelId: String) async throws -> TranscriptionOutcome
}
