# CLAUDE.md — WhisprLocal

> This file loads into every Claude Code session automatically. Keep it dense, high-signal, and up to date.

## What this project is

**WhisprLocal** is a fully on-device voice-to-text iOS app with a companion custom keyboard. Modeled on Wispr Flow, Recast, and Ghostpepper — but 100% local. No cloud. No telemetry. Open-source models only (Whisper, Qwen, Gemma, Llama, Phi).

Two targets:
- **WhisprLocalApp** — main iOS app. Runs Whisper (ASR) + MLX Swift (LLM polish). Full RAM budget.
- **WhisprKeyboard** — custom keyboard extension. Captures audio, hands off to main app via App Group. **Hard-capped at 48MB RAM — no ML models here, ever.**

## The five non-negotiables

1. **Local-only.** No network calls at runtime except user-initiated Hugging Face model downloads.
2. **Model-pluggable.** Users pick STT + LLM models from a JSON catalog. Nothing is hardcoded.
3. **Keyboard is dumb.** It captures audio and inserts text. All ML happens in the main app.
4. **Privacy is the product.** No analytics. No crash SDK. ATS locked to `huggingface.co` only.
5. **Ship milestones in order.** M0 → M1 → … → M7. Never collapse or skip.

## Canonical references

- **Full spec:** `PROJECT_SPEC.md` — the source of truth. Read it if anything is ambiguous.
- **Architecture:** `docs/ARCHITECTURE.md`
- **Privacy posture:** `docs/PRIVACY.md`
- **Model catalog:** `docs/MODEL_CATALOG.md`
- **Test matrix:** `docs/TEST_MATRIX.md`

## Build & test commands

### First-time setup (fresh clone)

```bash
# Install toolchain (one-time). Requires Homebrew and full Xcode 16+ at /Applications/Xcode.app
brew install xcodegen swiftlint mint
mint bootstrap                          # pins xcodegen + swiftlint versions from Mintfile
xcodegen generate                       # creates WhisprLocal.xcodeproj from project.yml
open WhisprLocal.xcodeproj
```

### Regular workflow

```bash
# Regenerate Xcode project from project.yml (run after any project.yml change)
xcodegen generate

# Build main app for simulator
xcodebuild -scheme WhisprLocalApp \
  -destination 'generic/platform=iOS Simulator' build

# Build keyboard extension
xcodebuild -scheme WhisprKeyboard \
  -destination 'generic/platform=iOS Simulator' build

# Run unit tests (main app + Shared package)
xcodebuild test -scheme WhisprLocalApp \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro'

# Lint
swiftlint --strict
```

Sim destination uses `OS=latest,name=iPhone <N> Pro` where `N` is the highest Pro
tier shipped with the installed Xcode. Pro tier matters because
`com.apple.developer.kernel.increased-memory-limit` behavior and Neural Engine
core counts differ from the non-Pro variants — using the Pro sim keeps test
conditions close to the iPhone 15 Pro / iPhone 16 Pro targets in
`PROJECT_SPEC.md` §2. Bump the device name when a new Xcode rev ships newer
Pro sims.

Do not invent build commands. If something here is stale, update this file.

Privacy / forbidden-pattern checks run via the `/audit-privacy` slash command
(dev) and via inline grep in `.github/workflows/ci.yml` (CI). Do **not** add a
standalone `scripts/audit-privacy.sh` — one source of truth.

## Code style

- Swift 5.10+. Use Swift 6 concurrency features where available.
- SwiftUI for all main-app UI. UIKit only inside the keyboard extension (`KeyboardViewController` is UIKit by platform requirement).
- One type per file. Filename matches type name.
- `// MARK: - Section` dividers in any file over ~100 lines.
- Dependency injection via initializers. No singletons except `FileManager.default`, `UserDefaults.standard`, `Bundle.main`.
- Async/await everywhere. Combine only if a specific API forces it.
- `Result` types for fallible operations that aren't `throws`.
- `@Observable` macro for view models (iOS 17+).

## Anti-patterns — do not do these

- **Do not add cloud fallbacks.** No OpenAI, Anthropic, Google Cloud, Azure. Not even "optional." This is the product's moat.
- **Do not load ML models in the keyboard extension.** A `WhisperKit` or `MLX` import in `WhisprKeyboard/` is a bug.
- **Do not use xcodegen's `entitlements:` key without inline `properties:`.** It silently clobbers hand-written entitlements files. Use the `CODE_SIGN_ENTITLEMENTS` build setting to reference them instead (see current `project.yml` for the pattern).
- **Do not add analytics SDKs.** No Mixpanel, no Segment, no Firebase, no Sentry, no Amplitude, no PostHog. Use `OSLog` + Xcode Organizer for diagnostics.
- **Do not persist audio.** WAV files in `inbox/` delete after transcription. Polished text in `outbox/` deletes within 60s of insertion.
- **Do not commit model weights.** No `.gguf`, `.safetensors`, `.mlmodelc`, or `.mlpackage` files in git — ever. Weights download at runtime to the app container.
- **Do not hardcode a specific model.** Always go through `ModelCatalog`. The catalog is the contract with the user.
- **Do not exceed iOS 17 minimum** without asking.
- **Do not add dependencies** beyond the ones listed in the spec without asking.
- **Do not silently change privacy posture.** Any new network call, new file write, new `Info.plist` key that touches privacy = stop and ask.
- **Do not set `CODE_SIGNING_ALLOWED: NO` on any build config** — even Debug. iOS Simulator uses ad-hoc signing ("-") for free; disabling signing strips the entitlements file from the binary at runtime, which silently breaks App Groups, Keychain, push notifications, and anything else entitlement-gated. Symptom: runtime "client is not entitled" errors with no build-time warning. Fix: leave signing enabled; use `CODE_SIGN_STYLE: Automatic` + `DEVELOPMENT_TEAM` blank for simulator-only Debug.

## Session workflow

1. **Plan first.** For any non-trivial task, post a numbered plan before editing files. I'll approve or redirect.
2. **Small commits.** Each commit compiles. Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`.
3. **Branch per milestone.** `milestone/M<n>-<slug>`. `main` is protected.
4. **Run `/spec-check`** at the start of every milestone to catch drift from `PROJECT_SPEC.md`.
5. **Run `/verify`** after every logical chunk. Do not move forward on a red build.
6. **Run `/audit-privacy`** at the end of every milestone.
7. **Run `/memory-check`** if you touched anything in `WhisprKeyboard/`.
8. **Verify CLI tools exist on the CI runner** before adding a workflow step that calls them. Check the `macos-15` image manifest at `github.com/actions/runner-images` rather than assuming availability — for example, `ripgrep` is not preinstalled and must be `brew install`ed in the workflow.

## Milestones

| ID | Scope | Status |
|---|---|---|
| M0 | Project skeleton, targets, entitlements, CI | Shipped (`v0.1.0-m0`) |
| M1 | Audio capture in main app (AVAudioEngine → 16kHz Float32 WAV) | Shipped (branch `milestone/M1-audio`, tag on merge) |
| M2 | WhisperKit integration, model catalog, first transcription | Shipped (branch `milestone/M2-whisperkit`, tag on merge) |
| M3 | MLX Swift polish, prompt templates, raw/polished toggle | — |
| M4 | Keyboard extension, App Group hand-off, Darwin notifications | — |
| M5 | Command Mode, Dictionary, Snippets | — |
| M6 | History, Settings, Onboarding, accessibility pass | — |
| M7 | Hardening, Privacy Audit screen, test matrix | — |

Update the Status column after each merge.

## When you're unsure

- **Ambiguous spec?** Ask. Do not guess.
- **Unknown API behavior?** Read the package's source/README. Do not assume.
- **Tempted to add a library?** Post the tradeoff, ask before adding.
- **About to touch privacy?** Stop and surface it explicitly.

## Files you should never touch without asking

- `Shared/Sources/WhisprShared/AppGroupPaths.swift` — changes break the IPC contract between app and keyboard.
- `Shared/Sources/WhisprShared/JobEnvelope.swift` — same.
- `Shared/Sources/WhisprShared/DarwinNotificationNames.swift` — renaming any constant silently breaks keyboard↔app handoff.
- Entitlements files.
- `project.yml` structural sections (you can add targets, don't reshape the existing ones).
