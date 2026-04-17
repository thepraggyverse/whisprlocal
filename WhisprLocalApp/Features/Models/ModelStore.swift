import Foundation
import Observation

/// Observable facade over the model catalog + selection + in-flight
/// download state. Owned at the app root and injected into the Settings
/// model picker and the Record screen (which reads `isReadyForTranscription`).
///
/// State lives on the main actor; progress callbacks from
/// `ModelDownloadService` arrive on arbitrary threads and get hopped onto
/// the main actor before touching `downloadStates`.
@Observable
@MainActor
final class ModelStore {

    /// Per-entry download state observed by the UI.
    enum DownloadState: Sendable, Equatable {
        case idle
        case downloading(fraction: Double)
        case completed
        case failed(String)
    }

    // MARK: - Inputs

    let catalog: ModelCatalog

    /// Currently-selected model id. Persisted write-side in M6 when SwiftData
    /// lands; in-memory only for M2.
    private(set) var selectedModelId: String

    /// Download state keyed by `ModelEntry.id`. Entries not in the map are
    /// considered `.idle`. Populated on download start / completion /
    /// failure and on app-launch hydration.
    private(set) var downloadStates: [String: DownloadState] = [:]

    // MARK: - Dependencies

    private let downloadService: ModelDownloading

    // MARK: - Init

    init(catalog: ModelCatalog, downloadService: ModelDownloading) {
        self.catalog = catalog
        self.downloadService = downloadService
        self.selectedModelId = catalog.defaultEntry?.id
            ?? catalog.entries.first?.id
            ?? ""
    }

    // MARK: - Derived

    var selectedEntry: ModelEntry? {
        catalog.entry(id: selectedModelId)
    }

    func state(for modelId: String) -> DownloadState {
        downloadStates[modelId] ?? .idle
    }

    /// True when the currently-selected model is known-downloaded AND not
    /// in a failed/downloading state. Drives the Record button gate.
    var isReadyForTranscription: Bool {
        guard let id = selectedEntry?.id else { return false }
        return state(for: id) == .completed
    }

    // MARK: - Intents

    /// Select a model by catalog id. No-op if the id isn't in the catalog.
    func select(modelId: String) {
        guard catalog.entry(id: modelId) != nil else { return }
        selectedModelId = modelId
    }

    /// Hydrate download states from disk. Call once at app startup so the
    /// picker doesn't show "Download" for a model that's already on disk.
    func hydrateFromDisk() async {
        for entry in catalog.entries {
            let downloaded = await downloadService.isDownloaded(entry: entry)
            if downloaded {
                downloadStates[entry.id] = .completed
            }
        }
    }

    /// Kick off a download and update `downloadStates` as it progresses.
    /// Idempotent — a second call while in-flight is a no-op (the service
    /// handles dedup).
    func download(entry: ModelEntry) async {
        downloadStates[entry.id] = .downloading(fraction: 0)
        do {
            _ = try await downloadService.download(
                entry: entry,
                progress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        // Don't overwrite a completed/failed state if a late
                        // progress callback arrives after the task returned.
                        if case .downloading = self?.state(for: entry.id) {
                            self?.downloadStates[entry.id] = .downloading(fraction: fraction)
                        }
                    }
                }
            )
            downloadStates[entry.id] = .completed
        } catch {
            downloadStates[entry.id] = .failed(error.localizedDescription)
        }
    }
}
