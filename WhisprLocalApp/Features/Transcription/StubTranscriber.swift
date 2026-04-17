import Foundation

/// Deterministic `Transcriber` for unit tests, previews, and UI smoke paths.
/// Does not touch the filesystem, the network, or WhisperKit.
struct StubTranscriber: Transcriber {

    let cannedText: String
    let detectedLanguage: String?
    let durationSeconds: Double

    init(
        cannedText: String = "hello world",
        detectedLanguage: String? = "en",
        durationSeconds: Double = 0.01
    ) {
        self.cannedText = cannedText
        self.detectedLanguage = detectedLanguage
        self.durationSeconds = durationSeconds
    }

    func transcribe(audioURL: URL, modelId: String) async throws -> TranscriptionOutcome {
        TranscriptionOutcome(
            modelId: modelId,
            audioURL: audioURL,
            rawText: cannedText,
            detectedLanguage: detectedLanguage,
            durationSeconds: durationSeconds,
            createdAt: Date()
        )
    }
}
