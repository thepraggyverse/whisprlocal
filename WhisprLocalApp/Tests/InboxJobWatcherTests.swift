import Foundation
import XCTest
@testable import WhisprLocalApp
import WhisprShared

@MainActor
final class InboxJobWatcherTests: XCTestCase {

    private var tempInbox: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempInbox = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("whispr-inbox-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempInbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempInbox)
        tempInbox = nil
        try super.tearDownWithError()
    }

    // MARK: - enumeratePairs

    func testEnumeratePairsFindsMatchingWAVAndJSON() throws {
        let jobId = UUID()
        let wavURL = try writeFakeWAV(jobId: jobId)
        let envelopeURL = try writeEnvelope(jobId: jobId)

        let pairs = InboxJobWatcher.enumeratePairs(in: tempInbox, fileManager: .default)

        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.jobId, jobId)
        XCTAssertEqual(pairs.first?.wav, wavURL)
        XCTAssertEqual(pairs.first?.envelope, envelopeURL)
    }

    func testEnumeratePairsIgnoresOrphanWAV() throws {
        _ = try writeFakeWAV(jobId: UUID())
        let pairs = InboxJobWatcher.enumeratePairs(in: tempInbox, fileManager: .default)
        XCTAssertTrue(pairs.isEmpty)
    }

    func testEnumeratePairsIgnoresOrphanJSON() throws {
        _ = try writeEnvelope(jobId: UUID())
        let pairs = InboxJobWatcher.enumeratePairs(in: tempInbox, fileManager: .default)
        XCTAssertTrue(pairs.isEmpty)
    }

    func testEnumeratePairsIgnoresNonUUIDFilenames() throws {
        try Data([0]).write(to: tempInbox.appendingPathComponent("not-a-uuid.wav"))
        try Data([0]).write(to: tempInbox.appendingPathComponent("not-a-uuid.json"))
        let pairs = InboxJobWatcher.enumeratePairs(in: tempInbox, fileManager: .default)
        XCTAssertTrue(pairs.isEmpty)
    }

    func testEnumeratePairsReturnsSortedByUUID() throws {
        let ids = (0..<5).map { _ in UUID() }
        for jobId in ids {
            _ = try writeFakeWAV(jobId: jobId)
            _ = try writeEnvelope(jobId: jobId)
        }

        let pairs = InboxJobWatcher.enumeratePairs(in: tempInbox, fileManager: .default)
        let sortedIds = ids.map(\.uuidString).sorted()
        XCTAssertEqual(pairs.map { $0.jobId.uuidString }, sortedIds)
    }

    // MARK: - scanAndProcess

    func testScanProcessesPairAndCleansUp() async throws {
        let jobId = UUID()
        let wavURL = try writeFakeWAV(jobId: jobId)
        let envelopeURL = try writeEnvelope(jobId: jobId)

        let store = TranscriptionStore()
        let stub = StubTranscriber(cannedText: "hello m2")
        let watcher = InboxJobWatcher(
            transcriber: stub,
            store: store,
            modelIdProvider: { "whisper-base" },
            inboxURLProvider: { [tempInbox] in tempInbox },
            retainInputsForDebug: false
        )

        await watcher.scanAndProcess()

        XCTAssertEqual(store.outcomes.count, 1)
        XCTAssertEqual(store.latest?.rawText, "hello m2")
        XCTAssertEqual(store.latest?.modelId, "whisper-base")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wavURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: envelopeURL.path))
    }

    func testScanSkipsWhenNoModelSelected() async throws {
        let jobId = UUID()
        let wavURL = try writeFakeWAV(jobId: jobId)
        let envelopeURL = try writeEnvelope(jobId: jobId)

        let store = TranscriptionStore()
        let watcher = InboxJobWatcher(
            transcriber: StubTranscriber(),
            store: store,
            modelIdProvider: { nil },
            inboxURLProvider: { [tempInbox] in tempInbox },
            retainInputsForDebug: false
        )

        await watcher.scanAndProcess()

        // No model → no processing, no cleanup. Files still present.
        XCTAssertTrue(store.outcomes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wavURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: envelopeURL.path))
    }

    func testScanCleansUpEvenWhenTranscribeThrows() async throws {
        let jobId = UUID()
        let wavURL = try writeFakeWAV(jobId: jobId)
        let envelopeURL = try writeEnvelope(jobId: jobId)

        let store = TranscriptionStore()
        let watcher = InboxJobWatcher(
            transcriber: AlwaysFailingTranscriber(),
            store: store,
            modelIdProvider: { "whisper-base" },
            inboxURLProvider: { [tempInbox] in tempInbox },
            retainInputsForDebug: false
        )

        await watcher.scanAndProcess()

        XCTAssertTrue(store.outcomes.isEmpty, "failure shouldn't add an outcome")
        // Spec §8.6 — inputs deleted even on failure.
        XCTAssertFalse(FileManager.default.fileExists(atPath: wavURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: envelopeURL.path))
    }

    func testScanProcessesMultiplePairs() async throws {
        for _ in 0..<3 {
            let jobId = UUID()
            _ = try writeFakeWAV(jobId: jobId)
            _ = try writeEnvelope(jobId: jobId)
        }

        let store = TranscriptionStore()
        let watcher = InboxJobWatcher(
            transcriber: StubTranscriber(),
            store: store,
            modelIdProvider: { "whisper-base" },
            inboxURLProvider: { [tempInbox] in tempInbox },
            retainInputsForDebug: false
        )

        await watcher.scanAndProcess()

        XCTAssertEqual(store.outcomes.count, 3)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: tempInbox,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(remaining.count, 0)
    }

    func testScanReturnsEarlyWhenInboxURLIsNil() async {
        let store = TranscriptionStore()
        let watcher = InboxJobWatcher(
            transcriber: StubTranscriber(),
            store: store,
            modelIdProvider: { "whisper-base" },
            inboxURLProvider: { nil },
            retainInputsForDebug: false
        )
        await watcher.scanAndProcess()
        XCTAssertTrue(store.outcomes.isEmpty)
    }

    // MARK: - Helpers

    @discardableResult
    private func writeFakeWAV(jobId: UUID) throws -> URL {
        let url = tempInbox.appendingPathComponent("\(jobId.uuidString).wav")
        // Stub content — the real transcriber is swapped for a stub in
        // these tests, so the WAV body is never parsed.
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }

    @discardableResult
    private func writeEnvelope(jobId: UUID) throws -> URL {
        let envelope = JobEnvelope(
            jobId: jobId,
            createdAt: Date(),
            sourceBundleId: "com.praggy.whisprlocal.app",
            pipeline: "default"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        let url = tempInbox.appendingPathComponent("\(jobId.uuidString).json")
        try data.write(to: url)
        return url
    }
}

// MARK: - Test doubles

/// Transcriber that always throws, for the failure-cleanup test.
private struct AlwaysFailingTranscriber: Transcriber {
    struct Failure: Error {}
    func transcribe(audioURL: URL, modelId: String) async throws -> TranscriptionOutcome {
        throw Failure()
    }
}
