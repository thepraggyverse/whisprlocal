# Model catalog

User-selectable speech-to-text and LLM polish models. The full catalog with
IDs, sizes, device compatibility, and sources is defined in
`PROJECT_SPEC.md` §4.

> **Status: stub.** This page is populated at **M2** (WhisperKit integration
> + first working transcription end-to-end), with the MLX/polish half
> detailed at **M3**. At M0 no model is downloaded or runnable — the
> placeholder exists so the docs tree matches the project structure per
> spec §9.

## What will live here

Once M2 lands, this document will include, for each model:

- The canonical **ID** (`whisper-base`, `qwen2.5-1.5b-instruct-4bit`, etc.).
- **Display name** as shown in Settings.
- **Hugging Face repo** and resolved download URL.
- **Size on disk** after download.
- **Minimum device RAM** and **minimum iOS version**.
- **Recommended use** — STT, polish, or Command Mode.
- **License** (all models shipped are MIT, Apache 2.0, or compatible
  permissive licenses).

See `WhisprLocalApp/Features/Models/ModelCatalog.swift` (forthcoming at M2)
for the canonical JSON representation that ships in the app bundle.

## Why a catalog, not a hardcoded choice?

Model-pluggable is one of the two non-negotiable differentiators for this
project (the other is local-only — see `PROJECT_SPEC.md` §2 and the
non-negotiables in `CLAUDE.md`). Every design decision is measured against
whether it preserves the user's freedom to pick a different model. The
catalog is the contract.
