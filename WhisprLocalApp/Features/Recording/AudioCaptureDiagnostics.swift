import AVFoundation
import Foundation
import OSLog

/// Temporary diagnostic helpers for `AudioCaptureService`. Introduced on
/// branch `fix/m2-audio-diagnostics` to track down an empty-transcript
/// bug on real devices (iPhone 17 Pro Max / iOS 26.4.1): Whisper returns
/// no text in ~0.01 s, suggesting silent or zero-length audio reaching
/// the engine despite a working mic.
///
/// Everything here should be removed (or collapsed into `OSLog.debug`)
/// once the root cause is identified and fixed. Kept in its own file so
/// `AudioCaptureService` stays under SwiftLint's class/file-length caps.
enum AudioCaptureDiagnostics {

    /// Raw (unscaled) RMS of the buffer — same math as
    /// `AudioCaptureService.rmsLevel` but without the ×4-clamp display
    /// adjustment. Speech produces ~0.02-0.1 here; silence produces
    /// < 0.001.
    static func rawRMS(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for idx in 0..<count {
            let sample = channel[idx]
            sum += sample * sample
        }
        return sqrtf(sum / Float(count))
    }

    /// Peak absolute sample amplitude in the buffer, in the PCM Float32
    /// 0...1-ish range. Complements `rawRMS` — when the average is low
    /// but peak is high, we're looking at sparse transients, not silence.
    static func peakAmplitude(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }
        let count = Int(buffer.frameLength)
        var maxAbs: Float = 0
        for idx in 0..<count {
            let abs = fabsf(channel[idx])
            if abs > maxAbs {
                maxAbs = abs
            }
        }
        return maxAbs
    }

    /// Per-tap diagnostic emit — logs rawRMS + peak every call, and the
    /// first 8 samples for the first three taps. Runs on the same serial
    /// queue as the tap write, so no atomicity work is needed.
    static func logTap(index: Int, buffer: AVAudioPCMBuffer, logger: Logger) {
        let rms = rawRMS(of: buffer)
        let peak = peakAmplitude(of: buffer)
        logger.info(
            "tap[\(index, privacy: .public)] frames=\(buffer.frameLength, privacy: .public) rawRMS=\(rms, privacy: .public) peak=\(peak, privacy: .public)"
        )
        if index < 3 {
            let first8 = firstSamples(of: buffer, count: 8)
            logger.info("tap[\(index, privacy: .public)] first8=\(first8, privacy: .public)")
        }
    }

    /// First `count` samples as a compact string for OSLog. Caller should
    /// bound `count` (≤ 16) so log lines stay readable.
    static func firstSamples(of buffer: AVAudioPCMBuffer, count: Int) -> String {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return "[]"
        }
        let bound = min(count, Int(buffer.frameLength))
        var pieces: [String] = []
        pieces.reserveCapacity(bound)
        for idx in 0..<bound {
            pieces.append(String(format: "%.6f", channel[idx]))
        }
        return "[" + pieces.joined(separator: ", ") + "]"
    }

    /// One-shot log of the input node's format — the raw audio shape the
    /// device is handing AVAudioEngine before our conversion step.
    @MainActor
    static func logInputFormat(_ format: AVAudioFormat, logger: Logger) {
        logger.info(
            "inputFormat sampleRate=\(format.sampleRate, privacy: .public) channels=\(format.channelCount, privacy: .public) commonFormat=\(format.commonFormat.rawValue, privacy: .public) interleaved=\(format.isInterleaved, privacy: .public)"
        )
    }

    /// One-shot log of AVAudioSession state right after we activate it.
    /// Surfaces mode (`.measurement` disables AGC — hypothesis-relevant),
    /// category options, and the currently-selected input/output route.
    @MainActor
    static func logSessionState(logger: Logger) {
        let session = AVAudioSession.sharedInstance()
        logger.info(
            "session category=\(session.category.rawValue, privacy: .public) mode=\(session.mode.rawValue, privacy: .public) options=\(session.categoryOptions.rawValue, privacy: .public) sampleRate=\(session.sampleRate, privacy: .public) otherAudio=\(session.isOtherAudioPlaying, privacy: .public)"
        )
        for input in session.currentRoute.inputs {
            logger.info(
                "session input port=\(input.portName, privacy: .public) type=\(input.portType.rawValue, privacy: .public) channels=\(input.channels?.count ?? 0, privacy: .public)"
            )
        }
        for output in session.currentRoute.outputs {
            logger.info(
                "session output port=\(output.portName, privacy: .public) type=\(output.portType.rawValue, privacy: .public)"
            )
        }
    }

    /// Re-reads the finalized WAV and logs size, frame count, duration,
    /// and whole-file RMS + peak. Runs synchronously on the main actor
    /// inside `stop()` — cheap for ≤ 10 s recordings.
    @MainActor
    static func logWAVStats(at url: URL, logger: Logger) {
        let name = url.lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? -1
        logger.info("WAV stats \(name, privacy: .public) size=\(size, privacy: .public)B")

        guard let file = try? AVAudioFile(forReading: url) else {
            logger.error("WAV stats: could not reopen \(name, privacy: .public) for reading")
            return
        }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        let duration = Double(file.length) / format.sampleRate
        logger.info(
            "WAV stats \(name, privacy: .public) sampleRate=\(format.sampleRate, privacy: .public) frames=\(frameCount, privacy: .public) duration=\(duration, privacy: .public)s"
        )

        guard frameCount > 0,
              let readBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            logger.info("WAV stats \(name, privacy: .public) zero frames — no audio was written")
            return
        }
        do {
            try file.read(into: readBuf)
            let rms = rawRMS(of: readBuf)
            let peak = peakAmplitude(of: readBuf)
            logger.info(
                "WAV stats \(name, privacy: .public) rawRMS=\(rms, privacy: .public) peak=\(peak, privacy: .public)"
            )
        } catch {
            logger.error(
                "WAV stats \(name, privacy: .public) re-read failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
