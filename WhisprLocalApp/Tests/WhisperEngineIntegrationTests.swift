import AVFoundation
import Foundation
import XCTest
@testable import WhisprLocalApp

/// End-to-end `WhisperEngine` exercise against a real WhisperKit download
/// and a real Core ML inference. **Opt-in** — skipped unless
/// `WHISPR_INTEGRATION=1` is set in the environment.
///
/// Default CI never runs these: they need network (model download ~40 MB
/// on first run), a warm Core ML cache, and a real iOS Simulator device.
/// Run manually from a developer machine with:
///
/// ```
/// WHISPR_INTEGRATION=1 xcodebuild test \
///   -scheme WhisprLocalApp \
///   -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
///   -only-testing:WhisprLocalAppTests/WhisperEngineIntegrationTests
/// ```
///
/// The test drives a procedurally-generated 2 s WAV of silence through the
/// engine. We do not assert a specific transcript — a real CC-licensed
/// audio fixture lands in M7 hardening per spec §10. For M2 the goal is
/// "the engine round-trips without crashing on iOS 26, honoring ADR-002's
/// three mitigations under real weights."
final class WhisperEngineIntegrationTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WHISPR_INTEGRATION"] == "1",
            "Integration test disabled — set WHISPR_INTEGRATION=1 to run."
        )
    }

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

        let engine = await WhisperEngine(catalog: catalog, modelFolderURL: modelFolder)

        let outcome = try await engine.transcribe(
            audioURL: wavURL,
            modelId: entry.id
        )

        XCTAssertEqual(outcome.modelId, entry.id)
        XCTAssertGreaterThan(outcome.durationSeconds, 0)
        // Do not assert outcome.rawText — silence may decode to an empty
        // string, a language marker, or a hallucinated token depending on
        // the variant's prompt prefill. Absence of crash is what we care
        // about at M2.
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
