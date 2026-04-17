import Foundation

/// Domain-layer transcription result. Decoupled from WhisperKit's own
/// `TranscriptionResult` so the rest of the app does not import WhisperKit
/// and M3's polish engine can extend this struct without leaking the
/// engine boundary.
struct TranscriptionOutcome: Sendable, Equatable, Hashable {

    /// Entry ID from `ModelCatalog` that produced this outcome.
    let modelId: String

    /// Source WAV URL inside App Group `inbox/`. May be deleted by the
    /// time a consumer reads this — treat as informational only.
    let audioURL: URL

    /// Raw transcription as returned by the STT engine. No cleanup
    /// applied. Polishing (M3) produces a separate field, not a mutation
    /// of this one.
    let rawText: String

    /// ISO-639-1-ish language code detected by the engine. `nil` if the
    /// engine could not determine a language (rare for supported audio).
    let detectedLanguage: String?

    /// Wall-clock time from transcribe-call-start to result-return, in
    /// seconds. Used for the "N seconds" badge in the UI and for M7's
    /// perf regressions.
    let durationSeconds: Double

    /// When the outcome was produced, not when the audio was recorded.
    let createdAt: Date
}
