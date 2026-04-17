import Foundation

/// Shared fixtures for SwiftUI previews. Not used at runtime. Kept in
/// the main target so `#Preview` blocks can reach them without a
/// separate preview-only target.
///
/// Guarded with `#if DEBUG` so preview-only wiring (including the
/// bundled-catalog load, which can fail noisily if the JSON is missing)
/// never runs in release builds.
#if DEBUG
enum PreviewFixtures {

    static let catalog: ModelCatalog = {
        // Previews should never hard-crash — fall back to an empty
        // catalog if the JSON is missing from the preview bundle. The
        // real app will trip `makeProduction()` instead.
        (try? ModelCatalog.loadBundled()) ?? ModelCatalog(schemaVersion: 1, entries: [])
    }()

    @MainActor
    static let modelStore: ModelStore = {
        ModelStore(catalog: catalog, downloadService: PreviewDownloader())
    }()

    @MainActor
    static let transcriptionStore: TranscriptionStore = {
        let store = TranscriptionStore()
        store.append(
            TranscriptionOutcome(
                modelId: "whisper-base",
                audioURL: URL(fileURLWithPath: "/tmp/preview.wav"),
                rawText: "This is a preview transcript.",
                detectedLanguage: "en",
                durationSeconds: 1.2,
                createdAt: Date()
            )
        )
        return store
    }()
}

private struct PreviewDownloader: ModelDownloading {
    func download(entry: ModelEntry, progress: (@Sendable (Double) -> Void)?) async throws -> URL {
        URL(fileURLWithPath: "/tmp/preview/\(entry.variantName)")
    }
    func isDownloaded(entry: ModelEntry) async -> Bool { false }
}
#endif
