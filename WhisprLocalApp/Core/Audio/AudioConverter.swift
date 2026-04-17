import AVFoundation
import Foundation
import WhisprShared

/// Converts arbitrary-format `AVAudioPCMBuffer`s (whatever the device's input
/// node hands us) into WhisprLocal's canonical capture format (16 kHz mono
/// Float32) via `AVAudioConverter`.
///
/// Create once per capture session with the device's native input format;
/// reuse for every buffer coming off the tap so the converter can maintain
/// its internal resampler state.
final class AudioConverter {

    enum ConverterError: Error {
        case initFailed
        case conversionFailed(NSError?)
    }

    let inputFormat: AVAudioFormat
    let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init(inputFormat: AVAudioFormat) throws {
        self.inputFormat = inputFormat

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFormat.sampleRate,
            channels: AVAudioChannelCount(AudioFormat.channelCount),
            interleaved: false
        ) else {
            throw ConverterError.initFailed
        }
        self.outputFormat = outputFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw ConverterError.initFailed
        }
        self.converter = converter
    }

    /// Converts a single input buffer. Returns `nil` for empty input.
    ///
    /// For sample-rate conversion the returned buffer's `frameLength` reflects
    /// the actual number of output frames produced, which will be
    /// approximately `inputFrames × (outputRate / inputRate)` with a small
    /// discrepancy from the resampler's prime buffer.
    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        guard input.frameLength > 0 else { return nil }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        // Slack covers resampler overshoot on short inputs.
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 1024

        guard let output = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            throw ConverterError.conversionFailed(nil)
        }

        var consumed = false
        var nsError: NSError?
        let status = converter.convert(to: output, error: &nsError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }

        if status == .error {
            throw ConverterError.conversionFailed(nsError)
        }
        return output
    }
}
