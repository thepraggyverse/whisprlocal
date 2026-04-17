import Foundation

/// Canonical audio format for WhisprLocal's capture → transcription pipeline.
///
/// Whisper expects 16 kHz mono Float32 PCM. The keyboard converts
/// `AVAudioEngine`'s input-node format to this target before writing the WAV.
/// Do not change these constants without updating `AudioCaptureService` and
/// verifying WhisperKit compatibility.
public enum AudioFormat {

    /// Sample rate in Hz. Whisper's required input.
    public static let sampleRate: Double = 16_000

    /// Mono.
    public static let channelCount: UInt32 = 1

    /// 32-bit floating point samples.
    public static let bitDepth: UInt32 = 32
}
