# Model catalog

User-selectable speech-to-text models shipped in M2. The LLM polish half
(§4.2 in `PROJECT_SPEC.md`) lands at M3. The authoritative JSON lives at
`WhisprLocalApp/Resources/ModelCatalog.json` and is loaded at runtime by
`ModelCatalog.loadBundled()` — this page mirrors that JSON, annotated.

The catalog is the **contract with the user**: model-pluggable is one
of the two non-negotiable differentiators for the product. Every model
here is MIT-licensed, downloaded on-demand from HuggingFace, and runs
entirely on-device.

## Current catalog (schema version 1)

### Speech-to-text (STT)

| ID | Display name | Size | Language | Min RAM | Use | Note |
|---|---|---|---|---|---|---|
| `whisper-tiny-en` | Whisper Tiny (English) | ~40 MB | en | any | stt | Fastest, English-only. Good for quick tests and low-RAM devices. |
| `whisper-base` | Whisper Base | ~75 MB | multilingual | any | stt | **Default.** Good for mixed-language users (Hindi, Marathi, English). |
| `whisper-small` | Whisper Small | ~250 MB | multilingual | 4 GB | stt | Higher accuracy; 100+ languages. Needs A15+ hardware. |
| `whisper-large-v3-turbo` | Whisper Large v3 Turbo | ~632 MB | multilingual | 8 GB | stt | Best accuracy. Recommended on iPhone 15 Pro+ (8 GB RAM). |

All entries resolve from HuggingFace repo `argmaxinc/whisperkit-coreml`
via the variant-name suffix visible in
`WhisprLocalApp/Resources/ModelCatalog.json` (`openai_whisper-base`,
etc.) — that's exactly the folder name WhisperKit expects in
`WhisperKitConfig.model`.

### Polish (LLM) — not yet shipped

M3 lands the LLM polish half of spec §4.2 (Qwen 2.5 1.5B default, Gemma,
Llama, Phi variants). This section will grow at that milestone.

## Field reference

Every entry in `ModelCatalog.json` carries the following keys. The
Swift-side type is `ModelEntry`.

| Field | Type | Purpose |
|---|---|---|
| `id` | string | Internal stable identifier (`whisper-base`). Safe to persist in user defaults. Renames are a breaking change. |
| `displayName` | string | Shown in Settings. |
| `variantName` | string | Exact folder on HuggingFace (e.g. `openai_whisper-base`). Passed to `WhisperKitConfig(model:)`. |
| `huggingFaceRepo` | string | Source repo, typically `argmaxinc/whisperkit-coreml`. |
| `sizeBytes` | int64 | Approximate download size, shown before the user commits. |
| `sha256` | string or null | Checksum. `null` today; verification lands in M7 hardening. |
| `language` | `"en"` or `"multilingual"` | Whether the model is English-only or multilingual. |
| `minDeviceRAMBytes` | int64 | Floor below which the picker greys the row out. `0` means "any supported device." |
| `minIOSVersion` | string | Informational. Every shipped entry requires ≥ 17.0 (the app's deployment target). |
| `recommendedUse` | `"stt"` / `"polish"` / `"command"` | Function this entry fills. M2 entries are all `stt`. |
| `license` | string | SPDX identifier. All shipped entries are MIT. |
| `isDefault` | bool | Exactly one entry in the shipped catalog is `true`. Surfaced via `ModelCatalog.defaultEntry`. |
| `note` | string | Short human-readable blurb for the picker. |

## Why this list?

- `whisper-tiny-en` — smallest + fastest. Target: low-end devices or
  users who want English-only latency. The integration test
  (`WhisperEngineIntegrationTests`) uses this variant to keep its
  one-time download under a minute.
- `whisper-base` — the **default**. Small enough to download over
  cellular (~75 MB), multilingual out of the box (including Hindi and
  Marathi, the author's test languages). Honors spec §4.1's stated
  default selection.
- `whisper-small` — the accuracy-conscious middle ground for users on
  iPhone 14 / iPhone 15 non-Pro.
- `whisper-large-v3-turbo` — top accuracy, gated at 8 GB RAM (iPhone
  15 Pro+, iPhone 16 Pro+). Turbo variant delivers roughly 5× faster
  decode than plain `large-v3` with minimal accuracy regression.

## Why a catalog, not a hardcoded choice?

Model-pluggable is one of the two non-negotiable differentiators for this
project (the other is local-only — see `PROJECT_SPEC.md` §2 and the
non-negotiables in `CLAUDE.md`). Every design decision is measured
against whether it preserves the user's freedom to pick a different
model. The catalog is the contract.

## How entries are added

1. Pick a variant from the
   [`argmaxinc/whisperkit-coreml`](https://huggingface.co/argmaxinc/whisperkit-coreml)
   repo. The folder name is the `variantName`.
2. Estimate `sizeBytes` from the folder's HF metadata.
3. Add an entry to `WhisprLocalApp/Resources/ModelCatalog.json`.
4. Update this page.
5. If the change affects `ModelEntry`'s Swift shape, bump
   `ModelCatalog.currentSchemaVersion` and add a migration.

## References

- Source of truth: `WhisprLocalApp/Resources/ModelCatalog.json`
- Swift types: `WhisprLocalApp/Features/Models/ModelEntry.swift` and
  `ModelCatalog.swift`
- Spec: `PROJECT_SPEC.md` §4
- Upstream: [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit)
