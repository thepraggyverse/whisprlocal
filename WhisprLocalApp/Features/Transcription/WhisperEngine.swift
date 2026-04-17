import Foundation
import OSLog
import WhisperKit

/// Production `Transcriber` built on top of WhisperKit 0.18.0 (from
/// `argmaxinc/argmax-oss-swift`). See ADR-002 for the pin rationale and
/// the three mitigations baked into this file:
///
/// 1. **supressTokens must be `[]`** — mitigates
///    [argmax-oss-swift#392](https://github.com/argmaxinc/argmax-oss-swift/issues/392)
///    (`SuppressTokensFilter` writes to a read-only `MLMultiArray` on iOS
///    26 when `[-1]` is passed). We explicitly construct `DecodingOptions`
///    with an empty array every call. Note: upstream field name is the
///    misspelled `supressTokens` (one "p"); do not "correct" it in our
///    call sites — it won't compile.
///
/// 2. **No `prewarmModels()`** — mitigates
///    [argmax-oss-swift#315](https://github.com/argmaxinc/argmax-oss-swift/issues/315)
///    (Swift 6 crash during prewarm). We compile under Swift 5.10 (see
///    `project.yml`) and never call `prewarmModels()`. Cold start pays a
///    1–2 s penalty on first transcribe per process; the UI should mask
///    that with a spinner.
///
/// 3. **Models live in Application Support/Models/** — keeps weights out
///    of the user-visible Files app and out of iCloud backup by default.
///    The engine does not create the directory; `ModelDownloadService`
///    (M2 commit 4) owns directory lifecycle.
actor WhisperEngine: Transcriber {

    enum EngineError: LocalizedError, Equatable {
        case modelNotInCatalog(String)
        case whisperKitInitFailed(String)
        case whisperKitTranscribeFailed(String)
        case noTranscriptionResult

        var errorDescription: String? {
            switch self {
            case .modelNotInCatalog(let id):
                return "Model '\(id)' is not in the shipped catalog."
            case .whisperKitInitFailed(let reason):
                return "Could not load WhisperKit: \(reason)"
            case .whisperKitTranscribeFailed(let reason):
                return "Transcription failed: \(reason)"
            case .noTranscriptionResult:
                return "WhisperKit returned no transcription result."
            }
        }
    }

    private let catalog: ModelCatalog
    private let modelFolderURL: URL
    private let logger = Logger(
        subsystem: "com.praggy.whisprlocal.app",
        category: "WhisperEngine"
    )

    /// Cached pipe keyed by model id. Invalidated when the caller switches
    /// model. We keep at most one loaded to stay within the main app's
    /// memory headroom (multiple loaded models would double model weight
    /// footprint with no user benefit).
    private var cached: (modelId: String, pipe: WhisperKit)?

    init(catalog: ModelCatalog, modelFolderURL: URL) {
        self.catalog = catalog
        self.modelFolderURL = modelFolderURL
    }

    // MARK: - Transcriber

    func transcribe(audioURL: URL, modelId: String) async throws -> TranscriptionOutcome {
        let pipe = try await loadPipeIfNeeded(modelId: modelId)

        let start = Date()
        let results: [TranscriptionResult]
        do {
            results = try await pipe.transcribe(
                audioPath: audioURL.path,
                decodeOptions: Self.makeDecodingOptions()
            )
        } catch {
            throw EngineError.whisperKitTranscribeFailed("\(error)")
        }

        guard let first = results.first else {
            throw EngineError.noTranscriptionResult
        }

        let duration = Date().timeIntervalSince(start)
        logger.info("Transcribed \(audioURL.lastPathComponent, privacy: .public) in \(duration, format: .fixed(precision: 2)) s")

        return TranscriptionOutcome(
            modelId: modelId,
            audioURL: audioURL,
            rawText: first.text,
            detectedLanguage: first.language,
            durationSeconds: duration,
            createdAt: Date()
        )
    }

    // MARK: - Mitigations (static helpers — exposed for test verification)

    /// The `DecodingOptions` value used on every transcribe call.
    /// Exposed so `WhisperEngineMitigationsTests` can assert the
    /// `supressTokens == []` invariant without needing a loaded model.
    ///
    /// Misspelling note: upstream's field is `supressTokens` (one "p").
    /// Do not rename in our call site — it would break the build.
    static func makeDecodingOptions() -> DecodingOptions {
        DecodingOptions(supressTokens: [])
    }

    /// The `WhisperKitConfig` used to load a model. Exposed so tests can
    /// assert the `prewarm == false` invariant and the modelFolder/modelRepo
    /// wiring without loading a real model.
    static func makeConfig(for entry: ModelEntry, modelFolderURL: URL) -> WhisperKitConfig {
        WhisperKitConfig(
            model: entry.variantName,
            modelRepo: entry.huggingFaceRepo,
            modelFolder: modelFolderURL.path,
            verbose: false,
            prewarm: false,
            load: true,
            download: true,
            useBackgroundDownloadSession: false
        )
    }

    // MARK: - Private

    private func loadPipeIfNeeded(modelId: String) async throws -> WhisperKit {
        if let cached, cached.modelId == modelId {
            return cached.pipe
        }

        guard let entry = catalog.entry(id: modelId) else {
            throw EngineError.modelNotInCatalog(modelId)
        }

        let config = Self.makeConfig(for: entry, modelFolderURL: modelFolderURL)
        logger.info("Loading WhisperKit model \(entry.variantName, privacy: .public)")

        let pipe: WhisperKit
        do {
            pipe = try await WhisperKit(config)
        } catch {
            throw EngineError.whisperKitInitFailed("\(error)")
        }

        cached = (modelId, pipe)
        return pipe
    }
}
