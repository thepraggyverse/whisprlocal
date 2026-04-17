import AVFoundation
import Foundation
import OSLog
import WhisprShared

/// Owns the full audio capture path for the main app at M1:
///
///     AVAudioEngine tap (device rate) → AudioConverter → 16 kHz mono Float32
///     → AVAudioFile write → App Group inbox/{uuid}.wav
///
/// State is main-actor isolated so the view can observe it directly. The
/// engine tap runs on the real-time audio thread; inside the tap closure we
/// only capture thread-safe references (converter, file, continuation) and
/// dispatch the conversion + file write onto a serial queue so no ObjC
/// filesystem work touches the audio thread.
@Observable
@MainActor
final class AudioCaptureService {

    enum State: Equatable {
        case idle
        case recording
        case finalizing
    }

    enum CaptureError: LocalizedError, Equatable {
        case invalidState(State)
        case appGroupContainerMissing
        case sessionActivationFailed
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidState(let state):
                return "Recorder was in \(state) state, cannot transition."
            case .appGroupContainerMissing:
                return "App Group container is unavailable — check the capability and entitlements."
            case .sessionActivationFailed:
                return "The audio session could not be activated."
            case .engineFailed(let reason):
                return "Audio engine failed: \(reason)"
            }
        }
    }

    private(set) var state: State = .idle

    /// Normalized 0...1 RMS levels, one value per engine tap buffer (~10 Hz
    /// at default buffer sizes). Consumed by the waveform view.
    let levelStream: AsyncStream<Float>
    private let levelContinuation: AsyncStream<Float>.Continuation

    private let permission: RecordingPermissionAuthority
    private let inboxURLProvider: @Sendable () -> URL?
    private let notificationCenter: DarwinNotificationCenter
    private let sourceBundleIdProvider: @Sendable () -> String?
    private let logger = Logger(subsystem: "com.praggy.whisprlocal.app", category: "AudioCapture")

    private var engine: AVAudioEngine?
    private var converter: AudioConverter?
    private var outputFile: AVAudioFile?
    private var currentFileURL: URL?
    private let serialQueue = DispatchQueue(
        label: "com.praggy.whisprlocal.capture",
        qos: .userInitiated
    )

    init(
        permission: RecordingPermissionAuthority = AVRecordingPermissionAuthority(),
        inboxURLProvider: @escaping @Sendable () -> URL? = { AppGroupPaths.inboxURL },
        notificationCenter: DarwinNotificationCenter = SystemDarwinNotificationCenter(),
        sourceBundleIdProvider: @escaping @Sendable () -> String? = { Bundle.main.bundleIdentifier }
    ) {
        self.permission = permission
        self.inboxURLProvider = inboxURLProvider
        self.notificationCenter = notificationCenter
        self.sourceBundleIdProvider = sourceBundleIdProvider
        let (stream, continuation) = AsyncStream.makeStream(of: Float.self)
        self.levelStream = stream
        self.levelContinuation = continuation
    }

    deinit {
        levelContinuation.finish()
    }

    // MARK: - Public API

    /// Caller must confirm mic permission before invoking. Fails fast if the
    /// App Group container is unavailable (unit test w/o entitlement).
    func start() async throws {
        guard state == .idle else {
            throw CaptureError.invalidState(state)
        }
        let inboxURL = try resolveInboxURL()
        try activateSession()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw CaptureError.engineFailed("input sample rate is 0 — no microphone?")
        }

        let converter = try makeConverter(inputFormat: inputFormat)
        let fileURL = inboxURL.appendingPathComponent("\(UUID().uuidString).wav")
        let file = try openOutputFile(at: fileURL, outputFormat: converter.outputFormat)

        self.engine = engine
        self.converter = converter
        self.outputFile = file
        self.currentFileURL = fileURL

        AudioCaptureDiagnostics.logInputFormat(inputFormat, logger: logger)
        AudioCaptureDiagnostics.logSessionState(logger: logger)

        installTap(on: inputNode, inputFormat: inputFormat, converter: converter, file: file)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw CaptureError.engineFailed("engine.start() failed: \(error)")
        }

        state = .recording
        logger.info("Recording started → \(fileURL.lastPathComponent, privacy: .public)")
    }

    /// Stops the engine, flushes the write queue, applies file protection,
    /// and returns the URL of the finalized WAV.
    @discardableResult
    func stop() async throws -> URL {
        guard state == .recording else {
            throw CaptureError.invalidState(state)
        }
        state = .finalizing

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()

        await flushSerialQueue()

        // Closing the AVAudioFile (via dropping the strong reference)
        // finalizes the RIFF header on disk.
        outputFile = nil

        guard let url = currentFileURL else {
            state = .idle
            throw CaptureError.engineFailed("no current file URL at stop")
        }

        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
            logger.error("Setting file protection failed: \(error.localizedDescription)")
        }

        AudioCaptureDiagnostics.logWAVStats(at: url, logger: logger)

        // IPC handoff: write {uuid}.json envelope alongside the WAV and post
        // DarwinNotificationNames.jobQueued so the InboxJobWatcher picks up
        // the pair. Failures here are logged but do not fail stop() — the
        // WAV is still valid and a later scan will catch the orphan.
        do {
            try JobHandoff.writeEnvelopeAndPostJobQueued(
                forWAV: url,
                createdAt: Date(),
                sourceBundleId: sourceBundleIdProvider(),
                pipeline: "default",
                notificationCenter: notificationCenter
            )
        } catch {
            logger.error("Job handoff failed: \(error.localizedDescription)")
        }

        engine = nil
        converter = nil
        currentFileURL = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        state = .idle
        logger.info("Recording finalized: \(url.lastPathComponent, privacy: .public)")
        return url
    }

    /// Abandons the current recording. Deletes the partial WAV.
    func cancel() async {
        guard state == .recording else { return }
        state = .finalizing

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()

        await flushSerialQueue()
        outputFile = nil

        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        engine = nil
        converter = nil
        currentFileURL = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        state = .idle
    }

    // MARK: - Helpers

    private func resolveInboxURL() throws -> URL {
        guard let inboxURL = inboxURLProvider() else {
            throw CaptureError.appGroupContainerMissing
        }
        try FileManager.default.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
        return inboxURL
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            logger.error("Audio session activation failed: \(error.localizedDescription)")
            throw CaptureError.sessionActivationFailed
        }
    }

    private func makeConverter(inputFormat: AVAudioFormat) throws -> AudioConverter {
        do {
            return try AudioConverter(inputFormat: inputFormat)
        } catch {
            throw CaptureError.engineFailed("converter init failed: \(error)")
        }
    }

    private func openOutputFile(at url: URL, outputFormat: AVAudioFormat) throws -> AVAudioFile {
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw CaptureError.engineFailed("AVAudioFile open failed: \(error)")
        }
    }

    private func installTap(
        on inputNode: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        converter: AudioConverter,
        file: AVAudioFile
    ) {
        // Capture local references so the tap closure does not touch self.
        let tapQueue = serialQueue
        let tapConverter = converter
        let tapContinuation = levelContinuation
        let tapLogger = logger
        // outputFile is captured via a box so cancel() can clear it and
        // subsequent tap callbacks become no-ops.
        let fileBox = AudioFileBox(file: file)

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat
        ) { buffer, _ in
            tapQueue.async {
                guard let boxedFile = fileBox.file else { return }
                guard let converted = try? tapConverter.convert(buffer) else { return }
                do {
                    try boxedFile.write(from: converted)
                } catch {
                    tapLogger.error("WAV write failed: \(error.localizedDescription)")
                    return
                }

                // Diagnostic: log tap index + RMS + peak (and first
                // samples for the first few taps) via the helper that
                // keeps this closure short enough to fit SwiftLint's
                // class-body budget.
                let idx = fileBox.tapCount
                fileBox.tapCount = idx + 1
                AudioCaptureDiagnostics.logTap(index: idx, buffer: converted, logger: tapLogger)

                let level = Self.rmsLevel(of: converted)
                tapContinuation.yield(level)
            }
        }
    }

    private func flushSerialQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            serialQueue.async {
                continuation.resume()
            }
        }
    }

    nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for idx in 0..<count {
            let sample = channel[idx]
            sum += sample * sample
        }
        let rms = sqrtf(sum / Float(count))
        // The waveform UI expects 0...1. Speech RMS rarely exceeds ~0.25 on
        // the 16 kHz float path, so scale x4 and clamp for a lively bar.
        return min(1.0, rms * 4.0)
    }

}

/// Small reference box so the tap closure can read the in-flight AVAudioFile
/// without a strong capture of the capture service itself. `cancel()` clears
/// `file` to make subsequent tap ticks no-ops. `tapCount` is bumped inside
/// the serial tap queue for diagnostic log tagging.
private final class AudioFileBox: @unchecked Sendable {
    var file: AVAudioFile?
    var tapCount: Int = 0
    init(file: AVAudioFile) { self.file = file }
}
