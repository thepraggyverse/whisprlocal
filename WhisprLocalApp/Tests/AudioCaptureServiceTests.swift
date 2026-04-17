import AVFoundation
import XCTest
@testable import WhisprLocalApp
import WhisprShared

@MainActor
final class AudioCaptureServiceTests: XCTestCase {

    func testInitialStateIsIdle() {
        let service = AudioCaptureService(inboxURLProvider: { nil })
        XCTAssertEqual(service.state, .idle)
    }

    func testStartFailsIfAppGroupMissing() async {
        let service = AudioCaptureService(inboxURLProvider: { nil })
        do {
            try await service.start()
            XCTFail("expected error")
        } catch let error as AudioCaptureService.CaptureError {
            XCTAssertEqual(error, .appGroupContainerMissing)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testStopFromIdleThrowsInvalidState() async {
        let service = AudioCaptureService(inboxURLProvider: { nil })
        do {
            _ = try await service.stop()
            XCTFail("expected error")
        } catch let error as AudioCaptureService.CaptureError {
            if case .invalidState(let state) = error {
                XCTAssertEqual(state, .idle)
            } else {
                XCTFail("unexpected variant: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Bugbot #4 regression — fileBox is actually cleared

    /// The installTap comment promised that `cancel()` and `stop()` clear
    /// `fileBox.file` so any straggling tap callback becomes a no-op. Pre-
    /// fix, `fileBox` was a local variable in `installTap` — nothing could
    /// reach it. This test pins the contract: after a failed `start()`
    /// (which is the only failure path our unit test can reliably drive
    /// through `installTap`), the service's fileBox is nil.
    func testFileBoxIsClearedAfterStartFailure() async throws {
        let tempInbox = try makeTempInbox()
        defer { try? FileManager.default.removeItem(at: tempInbox) }

        struct SimulatedEngineStartFailure: Error {}

        let service = AudioCaptureService(
            inboxURLProvider: { tempInbox },
            engineStarter: { _ in throw SimulatedEngineStartFailure() }
        )

        do {
            try await service.start()
            XCTFail("expected engineStarter to throw")
        } catch is AudioCaptureService.CaptureError {
            // Expected.
        } catch {
            throw XCTSkip("skipping — start() bailed before engineStarter: \(error)")
        }

        let snapshot = service.stateSnapshotForTests
        XCTAssertFalse(
            snapshot.hasFileBox,
            "fileBox reference must be cleared — otherwise the installTap comment's claim that cancel/stop neutralize the tap's write path is a lie."
        )
    }

    // MARK: - Bugbot #2 regression — start() failure cleanup

    func testStartFailureClearsStateAndDeletesOrphanWAV() async throws {
        let tempInbox = try makeTempInbox()
        defer { try? FileManager.default.removeItem(at: tempInbox) }

        struct SimulatedEngineStartFailure: Error {}

        let service = AudioCaptureService(
            inboxURLProvider: { tempInbox },
            engineStarter: { _ in throw SimulatedEngineStartFailure() }
        )

        // Pre-condition: inbox is empty.
        let before = try FileManager.default.contentsOfDirectory(at: tempInbox, includingPropertiesForKeys: nil)
        XCTAssertTrue(before.isEmpty, "inbox should start empty")

        do {
            try await service.start()
            XCTFail("expected engineStarter to surface a failure")
        } catch is AudioCaptureService.CaptureError {
            // Expected: start() wraps the injected failure in .engineFailed.
        } catch {
            // Allowed: earlier-path failure (e.g. .sessionActivationFailed)
            // on a simulator without a mic. Only the wrapped
            // engineStarter path asserts the cleanup contract; bail out if
            // we never reached it.
            throw XCTSkip("skipping — start() bailed before engineStarter: \(error)")
        }

        // State must be fully reset — no leaked engine, converter, or
        // partially-open WAV on retry.
        let snapshot = service.stateSnapshotForTests
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertFalse(snapshot.hasEngine, "engine reference leaked after failure")
        XCTAssertFalse(snapshot.hasConverter, "converter reference leaked after failure")
        XCTAssertFalse(snapshot.hasOutputFile, "outputFile reference leaked after failure")
        XCTAssertNil(snapshot.currentFileURL, "currentFileURL leaked after failure")
        // Bugbot #4 cross-check: the tap file-box must be cleared too so
        // any straggling serial-queue block short-circuits instead of
        // writing into a neutralized WAV.
        XCTAssertFalse(snapshot.hasFileBox, "fileBox reference leaked after failure")

        // And the zero-byte orphan WAV on disk must be gone — otherwise
        // every retry grows the App Group inbox and the InboxJobWatcher
        // would later try to transcribe an empty file.
        let after = try FileManager.default.contentsOfDirectory(at: tempInbox, includingPropertiesForKeys: nil)
        let wavFiles = after.filter { $0.pathExtension == "wav" }
        XCTAssertTrue(wavFiles.isEmpty, "orphan WAV not cleaned up: \(wavFiles.map { $0.lastPathComponent })")
    }

    private func makeTempInbox() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("whispr-capture-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRMSOfConstantBufferMatchesExpected() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1000)!
        buffer.frameLength = 1000
        let samples = buffer.floatChannelData![0]
        for idx in 0..<1000 { samples[idx] = 0.1 }

        // RMS(constant=0.1) = 0.1. Scaled ×4 → 0.4, clamped ≤ 1.
        let level = AudioCaptureService.rmsLevel(of: buffer)
        XCTAssertEqual(level, 0.4, accuracy: 1e-4)
    }

    func testRMSOfEmptyBufferIsZero() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        buffer.frameLength = 0
        XCTAssertEqual(AudioCaptureService.rmsLevel(of: buffer), 0)
    }

    // MARK: - writeEnvelopeAndPostJobQueued

    func testHandoffWritesDecodableEnvelopeAlongsideWAV() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("whispr-handoff-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let jobId = UUID()
        let wavURL = tempDir.appendingPathComponent("\(jobId.uuidString).wav")
        try Data([0]).write(to: wavURL)

        let center = RecordingNotificationCenterSpy()
        let createdAt = Date(timeIntervalSince1970: 12345)
        try JobHandoff.writeEnvelopeAndPostJobQueued(
            forWAV: wavURL,
            createdAt: createdAt,
            sourceBundleId: "com.praggy.whisprlocal.app",
            pipeline: "default",
            notificationCenter: center
        )

        let envelopeURL = wavURL.deletingPathExtension().appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: envelopeURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: envelopeURL)
        let envelope = try decoder.decode(JobEnvelope.self, from: data)

        XCTAssertEqual(envelope.jobId, jobId)
        XCTAssertEqual(envelope.sourceBundleId, "com.praggy.whisprlocal.app")
        XCTAssertEqual(envelope.pipeline, "default")
        XCTAssertEqual(envelope.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testHandoffPostsJobQueuedNotification() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("whispr-handoff-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let jobId = UUID()
        let wavURL = tempDir.appendingPathComponent("\(jobId.uuidString).wav")
        try Data([0]).write(to: wavURL)

        let center = RecordingNotificationCenterSpy()
        try JobHandoff.writeEnvelopeAndPostJobQueued(
            forWAV: wavURL,
            createdAt: Date(),
            sourceBundleId: nil,
            pipeline: "default",
            notificationCenter: center
        )

        XCTAssertEqual(center.postedNames, [DarwinNotificationNames.jobQueued])
    }

    func testHandoffThrowsWhenWAVFilenameIsNotAUUID() {
        let wavURL = URL(fileURLWithPath: "/tmp/not-a-uuid.wav")
        let center = RecordingNotificationCenterSpy()
        XCTAssertThrowsError(
            try JobHandoff.writeEnvelopeAndPostJobQueued(
                forWAV: wavURL,
                createdAt: Date(),
                sourceBundleId: nil,
                pipeline: "default",
                notificationCenter: center
            )
        ) { error in
            guard case JobHandoff.HandoffError.wavFilenameNotAUUID(let stem) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(stem, "not-a-uuid")
        }
        XCTAssertTrue(center.postedNames.isEmpty, "should not post on failure")
    }
}

// MARK: - Darwin notification spy

/// Records every post, never observes. Used to verify that
/// `JobHandoff.writeEnvelopeAndPostJobQueued` fires exactly one
/// `jobQueued` notification per successful handoff.
private final class RecordingNotificationCenterSpy: DarwinNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var _postedNames: [String] = []

    var postedNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return _postedNames
    }

    func post(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        _postedNames.append(name)
    }

    func register(_ name: String, queue: DispatchQueue, callback: @escaping @Sendable () -> Void) -> Int32 {
        -1
    }

    func cancel(_ token: Int32) {}
}
