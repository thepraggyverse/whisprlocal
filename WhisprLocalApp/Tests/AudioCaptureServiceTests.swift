import AVFoundation
import XCTest
@testable import WhisprLocalApp

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

    // MARK: - Stub

    private struct StubAuthority: RecordingPermissionAuthority {
        let currentStatus: RecordingPermissionStatus
        let toReturn: RecordingPermissionStatus
        func request() async -> RecordingPermissionStatus { toReturn }
    }
}
