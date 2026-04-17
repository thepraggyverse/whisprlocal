import Foundation
import OSLog
import WhisperKit

/// Abstract boundary around model downloading. Lets `ModelStore` swap in a
/// fake for unit tests instead of hitting the network.
protocol ModelDownloading: Sendable {

    /// Download the weights for `entry` and return the resulting on-disk
    /// folder URL. Idempotent: if the weights are already present, returns
    /// immediately. Concurrent calls for the same entry id dedupe onto a
    /// single in-flight task.
    ///
    /// - Parameter progress: called on an arbitrary thread with a fraction
    ///   in `0.0...1.0`. Consumers should hop to `@MainActor` before
    ///   touching UI state.
    func download(
        entry: ModelEntry,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL

    /// Whether weights for this entry are already on disk in the folder
    /// managed by this service.
    func isDownloaded(entry: ModelEntry) async -> Bool
}

/// Production `ModelDownloading` that routes through
/// `WhisperKit.download(variant:progressCallback:)`. Weights land under
/// `Application Support/Models/` — out of the user-visible Files app and
/// out of iCloud backup by default.
///
/// Per spec §8.1, this is the **only** outbound network surface the app
/// should ever make. ATS in `project.yml` is allow-listed for exactly
/// `huggingface.co` + `cdn-lfs.huggingface.co` to enforce that at the
/// transport layer.
actor ModelDownloadService: ModelDownloading {

    /// Root folder where all model weights live.
    let modelFolderURL: URL

    /// In-flight download tasks keyed by `ModelEntry.id` for dedup.
    private var activeTasks: [String: Task<URL, Error>] = [:]

    /// Per-entry cache of the final variant folder after a successful
    /// download. Avoids a redundant filesystem probe on subsequent calls.
    private var resolvedFolders: [String: URL] = [:]

    private let logger = Logger(
        subsystem: "com.praggy.whisprlocal.app",
        category: "ModelDownloadService"
    )

    /// - Parameter modelFolderURL: destination root. Commonly
    ///   `Application Support/Models/`. Created if missing.
    init(modelFolderURL: URL) throws {
        self.modelFolderURL = modelFolderURL
        try FileManager.default.createDirectory(
            at: modelFolderURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: - ModelDownloading

    func download(
        entry: ModelEntry,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        // Dedupe concurrent calls.
        if let existing = activeTasks[entry.id] {
            return try await existing.value
        }

        // Idempotency: if we've already downloaded and the folder still exists,
        // return it immediately.
        if let cached = resolvedFolders[entry.id],
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let downloadBase = modelFolderURL
        let variant = entry.variantName
        let repo = entry.huggingFaceRepo
        logger.info("Downloading \(variant, privacy: .public) from \(repo, privacy: .public)")

        let task = Task { () -> URL in
            try await WhisperKit.download(
                variant: variant,
                downloadBase: downloadBase,
                useBackgroundSession: false,
                from: repo,
                token: nil,
                progressCallback: { reported in
                    progress?(reported.fractionCompleted)
                }
            )
        }
        activeTasks[entry.id] = task

        do {
            let resolved = try await task.value
            activeTasks[entry.id] = nil
            resolvedFolders[entry.id] = resolved
            logger.info("Downloaded \(variant, privacy: .public) → \(resolved.path, privacy: .public)")
            return resolved
        } catch {
            activeTasks[entry.id] = nil
            logger.error("Download failed for \(variant, privacy: .public): \(error.localizedDescription)")
            throw error
        }
    }

    func isDownloaded(entry: ModelEntry) async -> Bool {
        if let cached = resolvedFolders[entry.id],
           FileManager.default.fileExists(atPath: cached.path) {
            return true
        }
        // Best-effort probe — HubApi stores files under a nested
        // `models/<repo>/<variant>/` tree. A match here lets us remember the
        // path for next time.
        let candidates = [
            modelFolderURL
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(entry.huggingFaceRepo, isDirectory: true)
                .appendingPathComponent(entry.variantName, isDirectory: true),
            modelFolderURL.appendingPathComponent(entry.variantName, isDirectory: true)
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            resolvedFolders[entry.id] = candidate
            return true
        }
        return false
    }
}
