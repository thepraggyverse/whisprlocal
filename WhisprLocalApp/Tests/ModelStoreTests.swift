import XCTest
@testable import WhisprLocalApp

@MainActor
final class ModelStoreTests: XCTestCase {

    // MARK: - Fixtures

    private let tinyEntry = ModelEntry(
        id: "whisper-tiny-en",
        displayName: "Tiny EN",
        variantName: "openai_whisper-tiny.en",
        huggingFaceRepo: "argmaxinc/whisperkit-coreml",
        sizeBytes: 40_000_000,
        sha256: nil,
        language: .english,
        minDeviceRAMBytes: 0,
        minIOSVersion: "17.0",
        recommendedUse: .stt,
        license: "MIT",
        isDefault: false,
        note: ""
    )

    private let baseEntry = ModelEntry(
        id: "whisper-base",
        displayName: "Base",
        variantName: "openai_whisper-base",
        huggingFaceRepo: "argmaxinc/whisperkit-coreml",
        sizeBytes: 75_000_000,
        sha256: nil,
        language: .multilingual,
        minDeviceRAMBytes: 0,
        minIOSVersion: "17.0",
        recommendedUse: .stt,
        license: "MIT",
        isDefault: true,
        note: ""
    )

    private func makeCatalog() -> ModelCatalog {
        ModelCatalog(schemaVersion: 1, entries: [tinyEntry, baseEntry])
    }

    // MARK: - Initial state

    func testInitialSelectionIsCatalogDefault() {
        let store = ModelStore(catalog: makeCatalog(), downloadService: ImmediateFakeDownloader())
        XCTAssertEqual(store.selectedModelId, "whisper-base")
        XCTAssertEqual(store.selectedEntry?.id, "whisper-base")
    }

    func testInitialDownloadStatesAreIdle() {
        let store = ModelStore(catalog: makeCatalog(), downloadService: ImmediateFakeDownloader())
        XCTAssertEqual(store.state(for: "whisper-base"), .idle)
        XCTAssertEqual(store.state(for: "whisper-tiny-en"), .idle)
    }

    func testIsReadyIsFalseBeforeDownload() {
        let store = ModelStore(catalog: makeCatalog(), downloadService: ImmediateFakeDownloader())
        XCTAssertFalse(store.isReadyForTranscription)
    }

    // MARK: - Selection

    func testSelectChangesSelectedModel() {
        let store = ModelStore(catalog: makeCatalog(), downloadService: ImmediateFakeDownloader())
        store.select(modelId: "whisper-tiny-en")
        XCTAssertEqual(store.selectedModelId, "whisper-tiny-en")
    }

    func testSelectIgnoresUnknownId() {
        let store = ModelStore(catalog: makeCatalog(), downloadService: ImmediateFakeDownloader())
        store.select(modelId: "does-not-exist")
        XCTAssertEqual(store.selectedModelId, "whisper-base")
    }

    // MARK: - Download happy path

    func testDownloadTransitionsIdleToCompleted() async {
        let store = ModelStore(catalog: makeCatalog(), downloadService: ImmediateFakeDownloader())
        await store.download(entry: baseEntry)
        XCTAssertEqual(store.state(for: "whisper-base"), .completed)
    }

    func testDownloadMakesSelectedReadyForTranscription() async {
        let store = ModelStore(catalog: makeCatalog(), downloadService: ImmediateFakeDownloader())
        await store.download(entry: baseEntry)
        XCTAssertTrue(store.isReadyForTranscription)
    }

    // MARK: - Download failure

    func testDownloadFailureSetsFailedState() async {
        let store = ModelStore(
            catalog: makeCatalog(),
            downloadService: FailingFakeDownloader(message: "offline")
        )
        await store.download(entry: baseEntry)
        XCTAssertEqual(store.state(for: "whisper-base"), .failed("offline"))
        XCTAssertFalse(store.isReadyForTranscription)
    }

    // MARK: - Hydration

    func testHydrateMarksAlreadyDownloadedEntriesCompleted() async {
        let downloader = SelectivelyDownloadedFake(downloadedIds: ["whisper-base"])
        let store = ModelStore(catalog: makeCatalog(), downloadService: downloader)
        await store.hydrateFromDisk()
        XCTAssertEqual(store.state(for: "whisper-base"), .completed)
        XCTAssertEqual(store.state(for: "whisper-tiny-en"), .idle)
    }
}

// MARK: - Test doubles

/// Resolves downloads instantly to a fake URL without touching disk.
private final class ImmediateFakeDownloader: ModelDownloading, @unchecked Sendable {
    func download(
        entry: ModelEntry,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        progress?(1.0)
        return URL(fileURLWithPath: "/tmp/fake/\(entry.variantName)")
    }

    func isDownloaded(entry: ModelEntry) async -> Bool { false }

    func resolvedFolderURL(for entry: ModelEntry) async -> URL? { nil }
}

/// Always fails with a given message.
private struct FailingFakeDownloader: ModelDownloading {
    let message: String

    func download(
        entry: ModelEntry,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        struct FakeError: LocalizedError {
            let msg: String
            var errorDescription: String? { msg }
        }
        throw FakeError(msg: message)
    }

    func isDownloaded(entry: ModelEntry) async -> Bool { false }

    func resolvedFolderURL(for entry: ModelEntry) async -> URL? { nil }
}

/// Reports a fixed set of ids as already downloaded; every other call fails.
private struct SelectivelyDownloadedFake: ModelDownloading {
    let downloadedIds: Set<String>

    func download(
        entry: ModelEntry,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        URL(fileURLWithPath: "/tmp/fake/\(entry.variantName)")
    }

    func isDownloaded(entry: ModelEntry) async -> Bool {
        downloadedIds.contains(entry.id)
    }

    func resolvedFolderURL(for entry: ModelEntry) async -> URL? {
        downloadedIds.contains(entry.id)
            ? URL(fileURLWithPath: "/tmp/fake/\(entry.variantName)")
            : nil
    }
}
