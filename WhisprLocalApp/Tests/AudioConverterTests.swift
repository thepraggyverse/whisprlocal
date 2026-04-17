import AVFoundation
import XCTest
@testable import WhisprLocalApp
import WhisprShared

final class AudioConverterTests: XCTestCase {

    func testResample48kStereoTo16kMono() throws {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let converter = try AudioConverter(inputFormat: inputFormat)

        let input = Self.makeConstantBuffer(
            format: inputFormat,
            seconds: 1.0,
            amplitudes: [0.4, 0.2] // L, R
        )
        let output = try XCTUnwrap(converter.convert(input))

        XCTAssertEqual(output.format.sampleRate, AudioFormat.sampleRate)
        XCTAssertEqual(output.format.channelCount, AudioFormat.channelCount)
        XCTAssertEqual(output.format.commonFormat, .pcmFormatFloat32)

        // 48k → 16k over 1 second: expect ~16_000 frames, allow 1% slack for
        // resampler prime buffer.
        let expected = Double(AudioFormat.sampleRate) // 16_000
        let actual = Double(output.frameLength)
        XCTAssertEqual(actual, expected, accuracy: expected * 0.01)
    }

    func testSameFormatPassthrough() throws {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFormat.sampleRate,
            channels: AVAudioChannelCount(AudioFormat.channelCount),
            interleaved: false
        )!
        let converter = try AudioConverter(inputFormat: inputFormat)

        let input = Self.makeConstantBuffer(
            format: inputFormat,
            seconds: 0.5,
            amplitudes: [0.3]
        )
        let output = try XCTUnwrap(converter.convert(input))

        XCTAssertEqual(output.frameLength, input.frameLength)
    }

    func testEmptyInputReturnsNil() throws {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        )!
        let converter = try AudioConverter(inputFormat: inputFormat)

        let empty = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 128)!
        empty.frameLength = 0

        XCTAssertNil(try converter.convert(empty))
    }

    // MARK: - Helpers

    /// Builds a non-zero buffer of the requested length filled with constant
    /// per-channel amplitudes. Constant signal is the simplest thing that
    /// survives both resampling and channel down-mix unambiguously.
    private static func makeConstantBuffer(
        format: AVAudioFormat,
        seconds: Double,
        amplitudes: [Float]
    ) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            let amp = amplitudes[ch % amplitudes.count]
            let ptr = buffer.floatChannelData![ch]
            for i in 0..<Int(frameCount) {
                ptr[i] = amp
            }
        }
        return buffer
    }
}
