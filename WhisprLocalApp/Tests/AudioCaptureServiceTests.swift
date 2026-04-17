import AVFoundation
import XCTest
@testable import WhisprLocalApp
import WhisprShared

@MainActor
final class AudioCaptureServiceTests: XCTestCase {

    func testInitialStateIsIdle() {
        let service = AudioCaptureService(
            permission: StubAuthority(currentStatus: .granted, toReturn: .granted),
            inboxURLProvider: { nil }
        )
        XCTAssertEqual(service.state, .idle)
    }

    func testStartFailsIfAppGroupMissing() async {
        let service = AudioCaptureService(
            permission: StubAuthority(currentStatus: .granted, toReturn: .granted),
            inboxURLProvider: { nil }
        )
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
        let service = AudioCaptureService(
            permission: StubAuthority(currentStatus: .granted, toReturn: .granted),
            inboxURLProvider: { nil }
        )
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

    // MARK: - Stub

    private struct StubAuthority: RecordingPermissionAuthority {
        let currentStatus: RecordingPermissionStatus
        let toReturn: RecordingPermissionStatus
        func request() async -> RecordingPermissionStatus { toReturn }
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
