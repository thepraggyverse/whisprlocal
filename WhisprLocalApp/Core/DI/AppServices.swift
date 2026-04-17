import Foundation
import OSLog

/// Lightweight service container wired at app launch. Holds the single
/// instances of the M2 service graph so the SwiftUI view tree can inject
/// them via `.environment(...)` and observe them as `@Observable`s.
///
/// Per spec §9 this lives in `Core/DI/`. If the graph grows further, this
/// is the file that grows — not the `@main` struct.
@MainActor
final class AppServices {

    let catalog: ModelCatalog
    let modelFolderURL: URL

    let downloadService: ModelDownloadService
    let engine: WhisperEngine
    let modelStore: ModelStore
    let transcriptionStore: TranscriptionStore
    let watcher: InboxJobWatcher

    private let logger = Logger(
        subsystem: "com.praggy.whisprlocal.app",
        category: "AppServices"
    )

    init(catalog: ModelCatalog, modelFolderURL: URL) {
        self.catalog = catalog
        self.modelFolderURL = modelFolderURL

        let download = ModelDownloadService(modelFolderURL: modelFolderURL)
        self.downloadService = download
        // The engine asks the download service for the *deep* folder URL
        // at load time. Passing the root (modelFolderURL) directly would
        // send WhisperKit looking for MelSpectrogram.mlmodelc in the wrong
        // directory — see ModelDownloading's path contract.
        self.engine = WhisperEngine(
            catalog: catalog,
            modelFolderProvider: { [download] entry in
                await download.resolvedFolderURL(for: entry)
            }
        )
        self.modelStore = ModelStore(catalog: catalog, downloadService: download)
        self.transcriptionStore = TranscriptionStore()

        // Capture the @Observable store locally so the InboxJobWatcher's
        // modelIdProvider closure captures a value type instead of the
        // whole container.
        let modelStore = self.modelStore
        self.watcher = InboxJobWatcher(
            transcriber: engine,
            store: transcriptionStore,
            modelIdProvider: { modelStore.selectedModelId }
        )
    }

    /// Run once at app launch: hydrate model state from disk and turn on
    /// the Darwin-notification-driven inbox watcher.
    func start() async {
        await modelStore.hydrateFromDisk()
        watcher.start()
    }

    // MARK: - Construction helpers

    /// Production graph. `ModelCatalog` loads from the app bundle;
    /// `Application Support/Models/` is the weights root (R6 — out of
    /// user-visible Files, out of iCloud backup by default).
    static func makeProduction() -> AppServices {
        let catalog: ModelCatalog
        do {
            catalog = try ModelCatalog.loadBundled()
        } catch {
            // The bundled JSON is a compile-time resource; a failure here
            // means the app binary is broken. Loud crash > silent degrade.
            fatalError("ModelCatalog.loadBundled failed: \(error)")
        }

        let folder: URL
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            folder = appSupport.appendingPathComponent("Models", isDirectory: true)
        } catch {
            fatalError("Could not resolve Application Support: \(error)")
        }

        return AppServices(catalog: catalog, modelFolderURL: folder)
    }
}
