import XCTest
import WhisperKit
@testable import WhisprLocalApp

/// Guards the three upstream-bug mitigations baked into `WhisperEngine`.
/// If any of these regress, the app risks an iOS 26 crash or cold-start
/// crash. See ADR-002 for the rationale.
final class WhisperEngineMitigationsTests: XCTestCase {

    // MARK: - argmax-oss-swift#392 — supressTokens must be []

    func testDecodingOptionsUseEmptySupressTokens() {
        let options = WhisperEngine.makeDecodingOptions()
        XCTAssertTrue(
            options.supressTokens.isEmpty,
            "argmax-oss-swift#392: supressTokens must be [] to avoid the iOS 26 SuppressTokensFilter crash."
        )
    }

    func testDecodingOptionsDefaultTaskIsTranscribe() {
        // Sanity — we want the default task, not translate, when the
        // constructor short-circuits everything else. If a future bump
        // changes the default, this surfaces it loudly.
        let options = WhisperEngine.makeDecodingOptions()
        XCTAssertEqual(options.task, .transcribe)
    }

    // MARK: - argmax-oss-swift#315 — no prewarm

    func testConfigDoesNotEnablePrewarm() {
        let entry = makeEntry()
        let folder = URL(fileURLWithPath: "/tmp/whispr-test-models", isDirectory: true)
        let config = WhisperEngine.makeConfig(for: entry, modelFolderURL: folder)
        XCTAssertEqual(
            config.prewarm,
            false,
            "argmax-oss-swift#315: prewarm must stay false — Swift 5.10 mode does not mask the prewarm crash."
        )
    }

    // MARK: - Model folder / repo / variant wiring

    func testConfigRoutesVariantIntoModelField() {
        let entry = makeEntry()
        let config = WhisperEngine.makeConfig(
            for: entry,
            modelFolderURL: URL(fileURLWithPath: "/tmp/whispr-test-models", isDirectory: true)
        )
        XCTAssertEqual(config.model, "openai_whisper-base")
    }

    func testConfigRoutesHuggingFaceRepoIntoModelRepoField() {
        let entry = makeEntry()
        let config = WhisperEngine.makeConfig(
            for: entry,
            modelFolderURL: URL(fileURLWithPath: "/tmp/whispr-test-models", isDirectory: true)
        )
        XCTAssertEqual(config.modelRepo, "argmaxinc/whisperkit-coreml")
    }

    func testConfigRoutesModelFolderURLIntoConfigFolder() {
        let folder = URL(fileURLWithPath: "/var/mobile/Library/Application Support/Models", isDirectory: true)
        let config = WhisperEngine.makeConfig(for: makeEntry(), modelFolderURL: folder)
        XCTAssertEqual(config.modelFolder, folder.path)
    }

    func testConfigDownloadDefaultsOn() {
        // M2 expects first-run download; commit 4 may orchestrate it via
        // ModelDownloadService, but the engine's own fallback path should
        // not hard-fail when weights are missing.
        let config = WhisperEngine.makeConfig(
            for: makeEntry(),
            modelFolderURL: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertTrue(config.download)
    }

    func testConfigBackgroundDownloadSessionDisabled() {
        // WhisperKit's background-session path uses its own URLSession; we
        // route downloads through ModelDownloadService instead (commit 4),
        // so leave this off to avoid a second session fighting ours.
        let config = WhisperEngine.makeConfig(
            for: makeEntry(),
            modelFolderURL: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertFalse(config.useBackgroundDownloadSession)
    }

    // MARK: - Transcriber-boundary smoke (stub-driven)

    func testStubTranscriberReturnsExpectedOutcome() async throws {
        let stub = StubTranscriber(cannedText: "hello m2", detectedLanguage: "en")
        let audioURL = URL(fileURLWithPath: "/tmp/fake.wav")
        let outcome = try await stub.transcribe(audioURL: audioURL, modelId: "whisper-base")
        XCTAssertEqual(outcome.rawText, "hello m2")
        XCTAssertEqual(outcome.modelId, "whisper-base")
        XCTAssertEqual(outcome.detectedLanguage, "en")
        XCTAssertEqual(outcome.audioURL, audioURL)
    }

    func testEngineRejectsUnknownModelId() async {
        let emptyCatalog = ModelCatalog(schemaVersion: 1, entries: [])
        let engine = WhisperEngine(
            catalog: emptyCatalog,
            modelFolderURL: URL(fileURLWithPath: "/tmp/whispr-test-models", isDirectory: true)
        )
        do {
            _ = try await engine.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/nope.wav"),
                modelId: "does-not-exist"
            )
            XCTFail("Expected WhisperEngine.EngineError.modelNotInCatalog")
        } catch WhisperEngine.EngineError.modelNotInCatalog(let id) {
            XCTAssertEqual(id, "does-not-exist")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Fixtures

    private func makeEntry() -> ModelEntry {
        ModelEntry(
            id: "whisper-base",
            displayName: "Whisper Base",
            variantName: "openai_whisper-base",
            huggingFaceRepo: "argmaxinc/whisperkit-coreml",
            sizeBytes: 75_000_000,
            sha256: nil,
            language: .multilingual,
            minDeviceRAMBytes: 0,
            minIOSVersion: "17.0",
            recommendedUse: .stt,
            license: "MIT",
            isDefault: true,
            note: "test"
        )
    }
}
