import AVFoundation
import Foundation
import WhisprShared

/// Writes an `AVAudioPCMBuffer` to disk as a RIFF/WAVE file with
/// `FileProtectionType.complete` applied per `PROJECT_SPEC.md §8.5`.
///
/// The buffer must already be in WhisprLocal's canonical capture format
/// (16 kHz mono Float32). `AudioCaptureService` owns the conversion from the
/// device-native input format to this target before calling here.
///
/// Header correctness is delegated to `AVAudioFile` — it handles the fmt/fact
/// chunks that the IEEE-float WAV spec (format code 3) requires, so downstream
/// readers (WhisperKit's audio loader) see a fully compliant file.
enum WAVWriter {

    enum WriterError: Error, Equatable {
        case unsupportedFormat(sampleRate: Double, channels: UInt32, isFloat: Bool)
    }

    static func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let fmt = buffer.format
        guard
            fmt.sampleRate == AudioFormat.sampleRate,
            fmt.channelCount == AudioFormat.channelCount,
            fmt.commonFormat == .pcmFormatFloat32
        else {
            throw WriterError.unsupportedFormat(
                sampleRate: fmt.sampleRate,
                channels: fmt.channelCount,
                isFloat: fmt.commonFormat == .pcmFormatFloat32
            )
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: fmt.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)

        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
}
