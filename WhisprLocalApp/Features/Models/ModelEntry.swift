import Foundation

/// One entry in the user-selectable model catalog. Codable shape mirrors
/// `WhisprLocalApp/Resources/ModelCatalog.json`.
///
/// Per `PROJECT_SPEC.md` §4, the catalog is the contract with the user —
/// "model-pluggable" is one of the two non-negotiable differentiators.
/// Adding a field here is an implicit schema version bump; tolerate the
/// bump only if the JSON on disk carries the new field too.
struct ModelEntry: Codable, Sendable, Equatable, Identifiable, Hashable {

    enum RecommendedUse: String, Codable, Sendable, Equatable {
        case stt
        case polish
        case command
    }

    enum Language: String, Codable, Sendable, Equatable {
        case english = "en"
        case multilingual
    }

    /// Internal stable identifier (e.g. "whisper-base"). Safe to persist in
    /// user defaults; renames are a breaking change.
    let id: String

    /// Display name shown in Settings.
    let displayName: String

    /// Exact WhisperKit model folder name on Hugging Face (e.g.
    /// "openai_whisper-base"). This is what we hand to
    /// `WhisperKitConfig(model:)` at load time.
    let variantName: String

    /// Hugging Face repo that hosts the variant, typically
    /// "argmaxinc/whisperkit-coreml".
    let huggingFaceRepo: String

    /// Approximate download size in bytes. Shown in the picker before the
    /// user commits to a download.
    let sizeBytes: Int64

    /// SHA-256 of the model archive, when known. Present as a contract hook
    /// for M7 hardening (checksum verification). `nil` is tolerated today.
    let sha256: String?

    let language: Language

    /// Minimum device RAM in bytes below which the model is marked
    /// unsupported. `0` means "any supported device".
    let minDeviceRAMBytes: Int64

    /// Minimum iOS version string (e.g. "17.0"). Currently informational —
    /// the app-wide deployment target is 17.0 already, so every shipped
    /// entry passes. Kept so the contract from spec §4 stays intact.
    let minIOSVersion: String

    let recommendedUse: RecommendedUse

    /// SPDX license identifier ("MIT", "Apache-2.0", ...).
    let license: String

    /// Exactly one entry in the shipped catalog should have this set to true.
    /// The catalog loader surfaces it via `ModelCatalog.defaultEntry`.
    let isDefault: Bool

    /// Short human-readable blurb shown in the model picker.
    let note: String

    /// Device-capability gate used by the picker to grey out unsupported
    /// rows. Accepts the device's physical RAM in bytes.
    func isSupportedOnDevice(ramBytes: Int64) -> Bool {
        ramBytes >= minDeviceRAMBytes
    }

    /// Public HF page for the variant, used only for "Learn more" links in
    /// Settings. WhisperKit's own download path does not go through this URL.
    var huggingFaceURL: URL? {
        URL(string: "https://huggingface.co/\(huggingFaceRepo)/tree/main/\(variantName)")
    }
}
