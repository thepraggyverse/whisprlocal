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

    private let inboxURLProvider: @Sendable () -> URL?
    private let notificationCenter: DarwinNotificationCenter
    private let sourceBundleIdProvider: @Sendable () -> String?
    private let engineStarter: @Sendable (AVAudioEngine) throws -> Void
    private let logger = Logger(subsystem: "com.praggy.whisprlocal.app", category: "AudioCapture")

    // These five are `internal` (not `private`) so the DEBUG-only testing
    // extension in AudioCaptureService+Testing.swift can read them. They
    // stay invisible outside this module.
    var engine: AVAudioEngine?
    var converter: AudioConverter?
    var outputFile: AVAudioFile?
    var currentFileURL: URL?
    // Strong handle to the box the tap closure reads from. Held here so
    // stop()/cancel() can clear `fileBox.file` before new tap buffers are
    // dispatched — any in-flight serial-queue block short-circuits on a
    // nil `file` and becomes a no-op.
    var fileBox: AudioFileBox?
    private let serialQueue = DispatchQueue(
        label: "com.praggy.whisprlocal.capture",
        qos: .userInitiated
    )

    init(
        inboxURLProvider: @escaping @Sendable () -> URL? = { AppGroupPaths.inboxURL },
        notificationCenter: DarwinNotificationCenter = SystemDarwinNotificationCenter(),
        sourceBundleIdProvider: @escaping @Sendable () -> String? = { Bundle.main.bundleIdentifier },
        engineStarter: @escaping @Sendable (AVAudioEngine) throws -> Void = { try $0.start() }
    ) {
        self.inboxURLProvider = inboxURLProvider
        self.notificationCenter = notificationCenter
        self.sourceBundleIdProvider = sourceBundleIdProvider
        self.engineStarter = engineStarter
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

        installTap(on: inputNode, inputFormat: inputFormat, converter: converter, file: file)

        engine.prepare()
        do {
            try engineStarter(engine)
        } catch {
            inputNode.removeTap(onBus: 0)

            // Pull the URL out before we drop state so we can clean up
            // the zero-byte WAV AVAudioFile already created on disk.
            // Without this cleanup each retry leaves another orphan .wav
            // behind in the App Group inbox; InboxJobWatcher would then
            // try to transcribe an empty file.
            let orphanURL = currentFileURL

            // Drop the AVAudioFile reference *before* removing the file
            // so the RIFF write handle is closed first; otherwise
            // removeItem can fail silently on some volumes.
            self.fileBox?.file = nil
            self.fileBox = nil
            self.outputFile = nil
            self.engine = nil
            self.converter = nil
            self.currentFileURL = nil

            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )

            if let orphanURL {
                try? FileManager.default.removeItem(at: orphanURL)
            }

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

        // Neutralize the tap's file handle first. Any serial-queue block
        // that squeezes through after removeTap + flush hits the `guard`
        // on a nil `file` and no-ops — no rogue writes into a file we're
        // about to finalize.
        fileBox?.file = nil
        fileBox = nil

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

        // Clear the tap's file reference so any straggling serial-queue
        // block short-circuits before we remove the underlying WAV.
        fileBox?.file = nil
        fileBox = nil

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

// MARK: - Setup helpers

extension AudioCaptureService {

    fileprivate func resolveInboxURL() throws -> URL {
        guard let inboxURL = inboxURLProvider() else {
            throw CaptureError.appGroupContainerMissing
        }
        try FileManager.default.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
        return inboxURL
    }

    fileprivate func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            logger.error("Audio session activation failed: \(error.localizedDescription)")
            throw CaptureError.sessionActivationFailed
        }
    }

    fileprivate func makeConverter(inputFormat: AVAudioFormat) throws -> AudioConverter {
        do {
            return try AudioConverter(inputFormat: inputFormat)
        } catch {
            throw CaptureError.engineFailed("converter init failed: \(error)")
        }
    }

    fileprivate func openOutputFile(at url: URL, outputFormat: AVAudioFormat) throws -> AVAudioFile {
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

    fileprivate func installTap(
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
        // The AVAudioFile is captured by the tap via a reference box. The
        // class also holds the box (self.fileBox) so stop() / cancel() can
        // clear `file` before any in-flight serial-queue block runs —
        // those blocks then short-circuit on the nil guard and no-op.
        let box = AudioFileBox(file: file)
        self.fileBox = box

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat
        ) { buffer, _ in
            tapQueue.async {
                guard let boxedFile = box.file else { return }
                guard let converted = try? tapConverter.convert(buffer) else { return }
                do {
                    try boxedFile.write(from: converted)
                } catch {
                    tapLogger.error("WAV write failed: \(error.localizedDescription)")
                    return
                }
                let level = Self.rmsLevel(of: converted)
                tapContinuation.yield(level)
            }
        }
    }

    fileprivate func flushSerialQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            serialQueue.async {
                continuation.resume()
            }
        }
    }
}

/// Reference box so the tap closure can read the in-flight AVAudioFile
/// without a strong capture of the capture service itself. The service
/// also holds this box so `stop()` and `cancel()` can clear `file` before
/// any pending serial-queue block runs — they then short-circuit on the
/// nil `file` guard and become no-ops.
final class AudioFileBox: @unchecked Sendable {
    var file: AVAudioFile?
    init(file: AVAudioFile) { self.file = file }
}
