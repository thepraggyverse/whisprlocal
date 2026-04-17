import AVFoundation
import Foundation
import XCTest
@testable import WhisprLocalApp

/// End-to-end `WhisperEngine` exercise against a real WhisperKit download
/// and a real Core ML inference. **Opt-in** — only compiled when the
/// `WHISPR_INTEGRATION` Swift compilation condition is set.
///
/// Default CI never runs these: they need network (model download ~40 MB
/// on first run), a warm Core ML cache, and a real iOS Simulator device.
/// Run manually from a developer machine with:
///
/// ```
/// xcodebuild test \
///   -scheme WhisprLocalApp \
///   -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
///   -only-testing:WhisprLocalAppTests/WhisperEngineIntegrationTests \
///   OTHER_SWIFT_FLAGS='$(inherited) -D WHISPR_INTEGRATION'
/// ```
///
/// The test drives a procedurally-generated 2 s WAV of silence through the
/// engine. We do not assert a specific transcript — a real CC-licensed
/// audio fixture lands in M7 hardening per spec §10. For M2 the goal is
/// "the engine round-trips without crashing on iOS 26, honoring ADR-002's
/// three mitigations under real weights, and the download→load path
/// contract (commit history: resolver fix) holds end-to-end."
///
/// Using `#if WHISPR_INTEGRATION` rather than an env-var `XCTSkipUnless`
/// because `xcodebuild test` does not propagate shell env vars to the
/// iOS Simulator's test-runner process — a compile-time flag is the
/// only reliable CLI-driven gate for this invocation shape.
#if WHISPR_INTEGRATION
final class WhisperEngineIntegrationTests: XCTestCase {

    func testTinyEnglishRoundTripOnSilence() async throws {
        let catalog = try ModelCatalog.loadBundled()
        guard let entry = catalog.entry(id: "whisper-tiny-en") else {
            return XCTFail("whisper-tiny-en missing from bundled catalog")
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("whispr-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let modelFolder = tempRoot.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        let wavURL = try Self.writeSilenceWAV(to: tempRoot, seconds: 2)

        // Use the real download service so the test exercises the same
        // download→resolve path the production app does. This is what
        // actually catches the download-vs-load path-mismatch regression.
        let downloader = ModelDownloadService(modelFolderURL: modelFolder)
        _ = try await downloader.download(entry: entry, progress: nil)
        guard let resolved = await downloader.resolvedFolderURL(for: entry) else {
            return XCTFail("resolvedFolderURL returned nil immediately after a successful download")
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resolved.appendingPathComponent("MelSpectrogram.mlmodelc").path),
            "Resolved folder must contain MelSpectrogram.mlmodelc — this is the load-path contract"
        )

        let engine = WhisperEngine(
            catalog: catalog,
            modelFolderProvider: { [downloader] entry in
                await downloader.resolvedFolderURL(for: entry)
            }
        )

        let outcome = try await engine.transcribe(
            audioURL: wavURL,
            modelId: entry.id
        )

        XCTAssertEqual(outcome.modelId, entry.id)
        XCTAssertGreaterThan(outcome.durationSeconds, 0)
        // Do not assert outcome.rawText — silence may decode to an empty
        // string, a language marker, or a hallucinated token depending on
        // the variant's prompt prefill. Absence of crash is what we care
        // about at M2; the M7 CC-audio fixture will add a content assertion.
    }

    // MARK: - Fixtures

    /// Writes 2 seconds of PCM Float32 16 kHz mono silence to a WAV file.
    /// Matches the format `AudioCaptureService` produces at M1, so the
    /// integration test exercises exactly the bytes WhisperKit would see
    /// in production.
    private static func writeSilenceWAV(to directory: URL, seconds: Double) throws -> URL {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "WhisperEngineIntegrationTests",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not construct 16 kHz mono Float32 format"]
            )
        }

        let frameCount = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "WhisperEngineIntegrationTests",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate PCM buffer"]
            )
        }
        buffer.frameLength = frameCount
        // Channel data is already zero-initialized by AVAudioPCMBuffer.

        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
        return fileURL
    }
}
#endif  // WHISPR_INTEGRATION
