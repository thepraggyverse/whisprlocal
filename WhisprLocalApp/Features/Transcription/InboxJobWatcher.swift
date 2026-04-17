import Foundation
import OSLog
import WhisprShared

/// Orchestrates the pickup side of the IPC contract defined in spec §2:
/// WAVs + envelopes land in App Group `inbox/`, a `jobQueued` Darwin
/// notification is posted, this watcher pairs files, transcribes, writes
/// the outcome to `TranscriptionStore`, and deletes both inputs per
/// spec §8.6 (auto-delete after transcription).
///
/// At M2 the only publisher is `AudioCaptureService` in-process. At M4
/// the keyboard extension takes over that role — this watcher gets it
/// "for free" because the notification and path contracts are stable
/// (`Shared/Sources/WhisprShared/AppGroupPaths.swift` +
/// `DarwinNotificationNames.swift`).
///
/// ### Design notes
/// - **Idempotent scan.** Darwin notifications can arrive out-of-order
///   relative to the file write (R8 in the M2 plan). Every tick does a
///   full inbox enumeration; we never trust the notification to identify
///   a specific file.
/// - **In-flight dedup.** `inFlightJobIds` prevents a second notification
///   firing during a long transcribe from processing the same WAV twice.
/// - **Cleanup is unconditional.** If transcription fails, we still
///   delete the inputs. Leaking audio beyond the job lifecycle violates
///   spec §8.6 more severely than losing a failed recording. Failures
///   are logged loudly via OSLog.
@MainActor
final class InboxJobWatcher {

    private let transcriber: any Transcriber
    private let store: TranscriptionStore
    private let modelIdProvider: @MainActor () -> String?
    private let inboxURLProvider: @Sendable () -> URL?
    private let notificationCenter: DarwinNotificationCenter
    private let fileManager: FileManager
    private let logger = Logger(
        subsystem: "com.praggy.whisprlocal.app",
        category: "InboxJobWatcher"
    )

    private var notifyToken: Int32 = -1
    private var inFlightJobIds: Set<UUID> = []

    init(
        transcriber: any Transcriber,
        store: TranscriptionStore,
        modelIdProvider: @escaping @MainActor () -> String?,
        inboxURLProvider: @escaping @Sendable () -> URL? = { AppGroupPaths.inboxURL },
        notificationCenter: DarwinNotificationCenter = SystemDarwinNotificationCenter(),
        fileManager: FileManager = .default
    ) {
        self.transcriber = transcriber
        self.store = store
        self.modelIdProvider = modelIdProvider
        self.inboxURLProvider = inboxURLProvider
        self.notificationCenter = notificationCenter
        self.fileManager = fileManager
    }

    deinit {
        if notifyToken != -1 {
            notificationCenter.cancel(notifyToken)
        }
    }

    // MARK: - Lifecycle

    /// Register the Darwin observer and kick off an initial orphan sweep.
    /// Safe to call multiple times — only the first registration sticks.
    func start() {
        if notifyToken == -1 {
            notifyToken = notificationCenter.register(
                DarwinNotificationNames.jobQueued,
                queue: .global(qos: .userInitiated)
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.scanAndProcess()
                }
            }
        }
        Task { @MainActor in
            await self.scanAndProcess()
        }
    }

    /// Deregister the Darwin observer. Safe to call even if `start()` was
    /// never called.
    func stop() {
        if notifyToken != -1 {
            notificationCenter.cancel(notifyToken)
            notifyToken = -1
        }
    }

    // MARK: - Scan + process

    /// Enumerate the inbox and transcribe every complete WAV+envelope
    /// pair. Idempotent; safe to call on every notification and at launch.
    /// Exposed `internal` so tests can drive it without touching the
    /// Darwin notification plumbing.
    func scanAndProcess() async {
        guard let inboxURL = inboxURLProvider() else {
            logger.debug("No inbox URL (likely unit-test environment).")
            return
        }
        guard let modelId = modelIdProvider() else {
            logger.info("No model selected — skipping scan.")
            return
        }

        let pairs = Self.enumeratePairs(in: inboxURL, fileManager: fileManager)
        for pair in pairs where !inFlightJobIds.contains(pair.jobId) {
            inFlightJobIds.insert(pair.jobId)
            await processJob(pair: pair, modelId: modelId)
            inFlightJobIds.remove(pair.jobId)
        }
    }

    // MARK: - Pair enumeration

    struct JobPair: Equatable {
        let jobId: UUID
        let wav: URL
        let envelope: URL
    }

    /// Scan `inboxURL` for `{uuid}.wav` + `{uuid}.json` pairs. Filenames
    /// whose stem does not parse as a `UUID` are ignored (they belong to
    /// whatever wrote them, not us).
    static func enumeratePairs(in inboxURL: URL, fileManager: FileManager) -> [JobPair] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let envelopesByStem: [String: URL] = Dictionary(uniqueKeysWithValues:
            contents
                .filter { $0.pathExtension == "json" }
                .map { ($0.deletingPathExtension().lastPathComponent, $0) }
        )

        return contents
            .filter { $0.pathExtension == "wav" }
            .compactMap { wavURL -> JobPair? in
                let stem = wavURL.deletingPathExtension().lastPathComponent
                guard
                    let jobId = UUID(uuidString: stem),
                    let envelopeURL = envelopesByStem[stem]
                else {
                    return nil
                }
                return JobPair(jobId: jobId, wav: wavURL, envelope: envelopeURL)
            }
            // Stable ordering by filename so processing is deterministic.
            .sorted(by: { $0.jobId.uuidString < $1.jobId.uuidString })
    }

    // MARK: - Per-job processing

    private func processJob(pair: JobPair, modelId: String) async {
        logger.info("Processing job \(pair.jobId.uuidString, privacy: .public)")

        do {
            let outcome = try await transcriber.transcribe(
                audioURL: pair.wav,
                modelId: modelId
            )
            store.append(outcome)
            logger.info(
                "Transcribed \(pair.jobId.uuidString, privacy: .public) in \(outcome.durationSeconds, format: .fixed(precision: 2)) s"
            )
        } catch {
            logger.error(
                "Transcription failed for \(pair.jobId.uuidString, privacy: .public): \(error.localizedDescription)"
            )
        }

        // Spec §8.6 — auto-delete audio WAVs from inbox/ after
        // transcription. We include the envelope and apply this on
        // failure too; keeping audio around "in case" leaks the privacy
        // contract. Failures must be diagnosed from logs, not from WAVs
        // sitting in the App Group.
        try? fileManager.removeItem(at: pair.wav)
        try? fileManager.removeItem(at: pair.envelope)
    }
}
