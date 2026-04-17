import AVFoundation
import XCTest
@testable import WhisprLocalApp
import WhisprShared

final class WAVWriterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WAVWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRoundTripCanonicalFormat() throws {
        let url = tempDir.appendingPathComponent("sine.wav")
        let buffer = try Self.makeSineBuffer(seconds: 1, amplitude: 0.5, frequency: 440)

        try WAVWriter.write(buffer, to: url)

        let readBack = try AVAudioFile(forReading: url)
        XCTAssertEqual(readBack.fileFormat.sampleRate, AudioFormat.sampleRate)
        XCTAssertEqual(readBack.fileFormat.channelCount, AudioFormat.channelCount)
        // AVAudioFile reports commonFormat based on the underlying PCM bytes;
        // for IEEE-float WAV this is .pcmFormatFloat32.
        XCTAssertEqual(readBack.processingFormat.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(
            readBack.length,
            AVAudioFramePosition(AudioFormat.sampleRate),
            "expected exactly 1 second of frames"
        )
    }

    func testRoundTripSamplesMatchWithinTolerance() throws {
        let url = tempDir.appendingPathComponent("sine.wav")
        let buffer = try Self.makeSineBuffer(seconds: 0.1, amplitude: 0.25, frequency: 220)

        try WAVWriter.write(buffer, to: url)

        let readBack = try AVAudioFile(forReading: url)
        let readBuffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: readBack.processingFormat,
            frameCapacity: AVAudioFrameCount(readBack.length)
        ))
        try readBack.read(into: readBuffer)

        let writtenCount = Int(buffer.frameLength)
        let readCount = Int(readBuffer.frameLength)
        XCTAssertEqual(writtenCount, readCount)

        let written = buffer.floatChannelData![0]
        let read = readBuffer.floatChannelData![0]
        for idx in 0..<min(writtenCount, readCount) {
            XCTAssertEqual(written[idx], read[idx], accuracy: 1e-5)
        }
    }

    func testFileProtectionComplete() throws {
        let url = tempDir.appendingPathComponent("protected.wav")
        let buffer = try Self.makeSineBuffer(seconds: 0.05, amplitude: 0.1, frequency: 1000)

        // Contract: `WAVWriter.write` applies NSFileProtectionComplete per
        // PROJECT_SPEC.md §8.5. If `setAttributes` had thrown we'd see an
        // error here; the iOS Simulator does not enforce Data Protection
        // (it runs on macOS) and `attributesOfItem` returns nil for
        // `.protectionKey` on sim, so we tolerate nil here and require
        // `.complete` on device.
        try WAVWriter.write(buffer, to: url)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attrs[.protectionKey] as? FileProtectionType
        #if targetEnvironment(simulator)
        XCTAssertTrue(
            protection == nil || protection == .complete,
            "simulator may report nil; device must report .complete (actual: \(String(describing: protection)))"
        )
        #else
        XCTAssertEqual(protection, .complete)
        #endif
    }

    func testRejectsNonCanonicalFormat() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024

        XCTAssertThrowsError(try WAVWriter.write(buffer, to: tempDir.appendingPathComponent("bad.wav"))) { error in
            guard case WAVWriter.WriterError.unsupportedFormat = error else {
                return XCTFail("expected unsupportedFormat, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private static func makeSineBuffer(
        seconds: Double,
        amplitude: Float,
        frequency: Double
    ) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFormat.sampleRate,
            channels: AVAudioChannelCount(AudioFormat.channelCount),
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(seconds * AudioFormat.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]
        let omega = 2.0 * .pi * frequency / AudioFormat.sampleRate
        for idx in 0..<Int(frameCount) {
            samples[idx] = amplitude * Float(sin(Double(idx) * omega))
        }
        return buffer
    }
}
