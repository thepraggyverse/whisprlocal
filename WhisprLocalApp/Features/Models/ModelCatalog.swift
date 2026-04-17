import Foundation

/// Immutable snapshot of the model catalog loaded from the app bundle's
/// `ModelCatalog.json`. The catalog is read-only at runtime; user selection
/// lives elsewhere (`ModelStore`).
///
/// Per `PROJECT_SPEC.md` §4, the catalog is data, not code — field additions
/// must land in JSON and Swift together and ride a `schemaVersion` bump.
struct ModelCatalog: Sendable, Equatable {

    /// Current schema version. Bumped when any required field is added or
    /// semantics change. Loader rejects a file whose `schemaVersion` exceeds
    /// this value (forward-incompatible).
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let entries: [ModelEntry]

    /// The entry marked `isDefault: true` in the JSON. Exactly one is
    /// expected; if zero or more than one are found, loading fails.
    var defaultEntry: ModelEntry? {
        entries.first(where: { $0.isDefault })
    }

    func entry(id: String) -> ModelEntry? {
        entries.first(where: { $0.id == id })
    }

    /// Entries that the given device can physically run. Does not filter by
    /// iOS version — the app's deployment target already rules that out.
    func supported(onDeviceRAMBytes ramBytes: Int64) -> [ModelEntry] {
        entries.filter { $0.isSupportedOnDevice(ramBytes: ramBytes) }
    }

    // MARK: - Loading

    enum LoadError: Error, Equatable {
        case resourceMissing
        case invalidJSON(String)
        case unsupportedSchemaVersion(Int)
        case noDefaultEntry
        case multipleDefaultEntries([String])
    }

    /// Decode a catalog from a raw JSON data blob. Validates the invariants
    /// the rest of the app depends on (schema version, exactly-one default).
    static func load(from data: Data) throws -> ModelCatalog {
        let raw: Wrapper
        do {
            raw = try JSONDecoder().decode(Wrapper.self, from: data)
        } catch {
            throw LoadError.invalidJSON("\(error)")
        }

        guard raw.schemaVersion <= currentSchemaVersion else {
            throw LoadError.unsupportedSchemaVersion(raw.schemaVersion)
        }

        let defaults = raw.models.filter(\.isDefault)
        switch defaults.count {
        case 0:
            throw LoadError.noDefaultEntry
        case 1:
            break
        default:
            throw LoadError.multipleDefaultEntries(defaults.map(\.id))
        }

        return ModelCatalog(schemaVersion: raw.schemaVersion, entries: raw.models)
    }

    /// Convenience: load the catalog shipped as `ModelCatalog.json` inside
    /// the main app bundle. Unit tests running with a host app hit the same
    /// resource through `Bundle.main`.
    static func loadBundled(in bundle: Bundle = .main) throws -> ModelCatalog {
        guard let url = bundle.url(forResource: "ModelCatalog", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    // MARK: - JSON shape

    private struct Wrapper: Decodable {
        let schemaVersion: Int
        let models: [ModelEntry]
    }
}
