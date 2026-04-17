# PROJECT_SPEC.md — WhisprLocal

> Source of truth for WhisprLocal. Loaded on demand by Claude Code via `/spec-check` and referenced from `CLAUDE.md`.

---

## 0. Role & Operating Mode (for the agent building this)

You are a **senior iOS engineer** with deep experience in SwiftUI, AVFoundation, Core ML, WhisperKit, MLX Swift, and iOS App Extensions. You are building a **production-quality, fully on-device voice-to-text iOS app with a companion custom keyboard**, modeled after Wispr Flow, Recast AI keyboard, and Ghostpepper (macOS) — but **100% local, zero cloud calls, zero telemetry** by default.

Operate in this sequence for every phase:
1. **Plan** — post a numbered checklist of what you will do before writing code.
2. **Build** — implement in small, compilable commits. After each commit, run `xcodebuild -scheme WhisprLocalApp -destination 'generic/platform=iOS Simulator' build` (or the project's configured equivalent) and paste the last 40 lines of output.
3. **Verify** — run the unit tests you wrote for that commit.
4. **Report** — one-paragraph summary of what landed, what's pending, what's risky.

Do **not** skip ahead. Do **not** add features outside the spec. If you hit ambiguity, stop and ask — do not guess.

---

## 1. Product Vision

**WhisprLocal** lets a user speak into their iPhone and get clean, formatted, ready-to-send text in any app — without a single byte leaving the device. Think "Wispr Flow, but open-source-model-powered and private by construction."

### Reference products (study these UX patterns, do NOT clone branding)
- **Wispr Flow** — hotkey-triggered dictation, AI cleanup of filler words, Command Mode for voice edits (e.g., "make this formal"), custom dictionary, cross-app insertion.
- **Recast AI Keyboard (iOS)** — voice-first keyboard replacement.
- **Ghostpepper (macOS)** — global dictation menubar app.

### What makes us different
- **Local-first, model-pluggable.** User picks the STT and LLM models from a curated catalog; nothing is hardcoded to a vendor.
- **No subscription, no account, no server.** Models download once from Hugging Face, then work offline forever.
- **Two surfaces, one brain.** A main app (rich UI, long-form sessions, LLM polish, history, settings) and a system-wide custom keyboard extension (quick dictation anywhere, text insertion via `UITextDocumentProxy`).

---

## 2. Hard Architectural Constraints (read before coding)

These are non-negotiable iOS platform facts. Internalize them before designing.

| Constraint | Implication |
|---|---|
| **Custom keyboard extensions are capped at ~48 MB RAM** ([confirmed, 2025](https://reactnative.dev/docs/app-extensions)) | The keyboard **cannot** run a Whisper model or an LLM directly. It must hand audio off to the main app. |
| Keyboards have **no network access without "Full Access"** and no background execution | Audio capture must happen in the keyboard's foreground lifetime, then be persisted to a shared App Group container. |
| Main app has full RAM budget (`com.apple.developer.kernel.increased-memory-limit` entitlement gives ~3–5 GB on modern iPhones) | Whisper + LLM polish run here. |
| MLX Swift and WhisperKit both require **Apple Silicon and iOS 16/17+** | Target iOS 17.0 minimum; recommend iPhone 12+ (A14 or later). |
| Audio must be 16 kHz mono Float32 for Whisper | Convert in AVAudioEngine tap before writing to disk. |

### The architecture that follows from these constraints

```
┌────────────────────────────────────────────────────────────────┐
│  WhisprLocalApp (Main App)        WhisprKeyboard (Extension)   │
│  ────────────────────────         ────────────────────────     │
│  • SwiftUI UI                     • KeyboardViewController     │
│  • WhisperKit (ASR)               • Mic capture → 16kHz PCM    │
│  • MLX Swift (LLM polish)         • Writes .wav + job.json to  │
│  • History, settings, dictionary    App Group container        │
│  • Model downloader               • Opens host app via URL     │
│  • Background session monitor       scheme to trigger          │
│         ▲                                processing            │
│         │                                    │                 │
│         └──── App Group: group.com.praggy.whisprlocal ─────────┘
│              (shared container + Darwin notifications)         │
└────────────────────────────────────────────────────────────────┘
```

**Processing flow:**
1. User taps WhisprKeyboard's mic button in any app.
2. Keyboard records audio → 16 kHz mono Float32 WAV → writes to App Group `inbox/{jobId}.wav` + `inbox/{jobId}.json` (metadata: source app bundle ID if available, timestamp, selected pipeline).
3. Keyboard posts a Darwin notification `com.praggy.whisprlocal.job.queued`.
4. If main app is foreground: it processes immediately. If backgrounded or not running: keyboard opens it via URL scheme `whisprlocal://process?jobId=…` (optional; user configurable — some flows can wait until user opens the app).
5. Main app runs WhisperKit transcribe → optional LLM polish → writes result to `outbox/{jobId}.txt`.
6. Keyboard polls App Group (or observes Darwin notification `com.praggy.whisprlocal.job.done`), reads the text, calls `textDocumentProxy.insertText(_:)`.
7. Both `inbox` and `outbox` entries are deleted after successful insertion.

Document this flow in `docs/ARCHITECTURE.md` as the first deliverable.

---

## 3. Tech Stack (locked)

- **Language:** Swift 5.10+ / Swift 6 where available
- **UI:** SwiftUI (iOS 17 target), UIKit only where required (keyboard extension)
- **Min iOS:** 17.0
- **Recommended device:** iPhone 12 / A14 or later (8 GB RAM preferred)
- **Build system:** Xcode 16+, Swift Package Manager for all dependencies
- **ASR:** [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT, on-device, CoreML-compiled Whisper variants)
- **LLM:** [MLX Swift Examples / mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) (MIT) — runs Qwen, Gemma, Llama, Phi families
- **Fallback LLM backend (optional, behind a feature flag):** [LocalLLMClient](https://github.com/tattn/LocalLLMClient) which wraps llama.cpp + MLX
- **Audio:** AVAudioEngine + AVAudioConverter
- **Persistence:** SwiftData for history/settings; FileManager + App Group container for audio hand-off
- **Model fetch:** Hugging Face Hub via [swift-transformers](https://github.com/huggingface/swift-transformers) (bundled inside WhisperKit) — download happens in main app only, never in the keyboard extension

Add no other third-party dependencies without explicit approval.

---

## 4. Model Catalog (user-selectable, not hardcoded)

Build a `ModelCatalog.swift` that ships the following curated list. The user picks from this list in Settings; the app downloads on first use. Store model metadata in JSON so it can be updated without a code change.

### 4.1 STT (Speech-to-Text) models

| ID | Display name | Size (Q4/Q8) | Target devices | Notes |
|---|---|---|---|---|
| `whisper-tiny-en` | Whisper Tiny (English) | ~40 MB | Any A14+ | Fastest, lower accuracy |
| `whisper-base` | Whisper Base (multilingual) | ~75 MB | Any A14+ | Good default |
| `whisper-small` | Whisper Small (multilingual) | ~250 MB | A15+ | Better accuracy, 100+ langs |
| `whisper-large-v3-turbo` | Whisper Large v3 Turbo | ~800 MB | A17 Pro+ / iPhone 15 Pro+ | Best accuracy, slower cold-start |
| `parakeet-v3` (stretch) | NVIDIA Parakeet V3 via Argmax Pro | TBD | A17+ | Only if free tier works; otherwise omit |

Default selection: `whisper-base` for multilingual users (including Hindi, Marathi, English mix), `whisper-tiny-en` as the fast fallback.

### 4.2 LLM polish models

| ID | Display name | Size (4-bit) | Target devices | Notes |
|---|---|---|---|---|
| `apple-foundation-3b` | Apple Foundation Model (iOS 26+) | 0 (OS-bundled) | iOS 26+ only | Zero download; prefer if available |
| `qwen2.5-1.5b-instruct-4bit` | Qwen 2.5 1.5B Instruct | ~900 MB | A14+ | Default pick — small, fast, multilingual |
| `qwen2.5-3b-instruct-4bit` | Qwen 2.5 3B Instruct | ~1.8 GB | A15+ with 6GB+ RAM | Better polish quality |
| `gemma-2-2b-it-4bit` | Gemma 2 2B Instruct | ~1.4 GB | A15+ | Strong English, decent multilingual |
| `gemma-3-4b-it-4bit` | Gemma 3 4B Instruct | ~2.4 GB | iPhone 15 Pro+ (8GB) | Highest-quality polish in catalog |
| `phi-3.5-mini-4bit` | Phi-3.5 Mini (3.8B) | ~2.2 GB | iPhone 15 Pro+ | Good reasoning for Command Mode |
| `llama-3.2-3b-instruct-4bit` | Llama 3.2 3B Instruct | ~1.9 GB | A15+ | Solid all-rounder |

Source the MLX-ready weights from the `mlx-community` org on Hugging Face.

Each model entry must include: `id`, `displayName`, `sizeBytes`, `huggingFaceRepo`, `minDeviceRAM`, `minIOSVersion`, `recommendedUse` (stt / polish / command), `license`, `downloadURL` (resolved at runtime).

On first launch, run a **device capability check** (`os_proc_available_memory`, chip ID) and mark incompatible models as "Not supported on this device" — do not let users pick them.

---

## 5. Feature Scope (MVP)

All four items are in scope. Build in this order; each must ship green-tested before the next begins.

### 5.1 Core — Capture + Transcribe + Copy
- Mic permission flow (NSMicrophoneUsageDescription: "WhisprLocal uses the microphone to transcribe your speech entirely on-device. No audio ever leaves your iPhone.")
- Big tappable record button in main app (push-to-talk and toggle modes, user preference)
- Visual waveform during recording
- WhisperKit transcription with progress indicator
- Automatic copy to clipboard on completion
- Manual "Insert via keyboard" button (documents the keyboard install flow)

### 5.2 LLM Polish
- After transcription, optionally run text through the selected polish LLM
- **System prompt templates** (editable in Settings), shipped defaults:
  - `polish_default` — "Rewrite the following dictated speech as clean, well-punctuated text. Remove filler words (um, uh, like, you know). Preserve the speaker's meaning, tone, and language. Do not add information. Do not summarize. Output only the rewritten text."
  - `polish_email` — same but optimized for email tone
  - `polish_message` — casual, short, for chat
  - `polish_code_comment` — for code editors
- Show both "raw" and "polished" side by side with a toggle
- Polish runs in < 3s on default model (Qwen 2.5 1.5B) for 200-word input on iPhone 15 Pro — if it doesn't, surface a perf warning and suggest downgrading

### 5.3 Command Mode (voice edits)
- User selects text → triggers Command Mode via a dedicated button or voice cue "Hey Whispr"
- Speaks a command: "make this formal", "turn this into bullet points", "translate to Hindi", "shorter", "add a greeting"
- LLM receives: `{instruction: <transcribed>, text: <selection>}` via a system prompt that forbids free-form replies and enforces "output only the edited text"
- Result replaces selection

### 5.4 Custom Dictionary + Snippets + History
- **Dictionary:** user-added proper nouns, acronyms, technical terms. Injected into Whisper's `prompt` field (initial tokens) to bias recognition. Also fed to the polish LLM in the system prompt so it preserves spelling.
- **Snippets:** voice shortcuts. User defines a cue ("insert my email") → expansion ("praggy@example.com"). Detected by the polish LLM with a tool-call style prompt, or via a simple regex pre-pass on the transcript before polish (pick the simpler path; document why).
- **History:** last 100 sessions stored in SwiftData with: timestamp, raw transcript, polished output, model used, duration, language. User can re-copy, delete, or export as `.txt` / `.md`. **History never leaves the device.** Add a "Clear all" + auto-purge after N days (user setting, default 30).

---

## 6. Keyboard Extension Scope

The keyboard (`WhisprKeyboard` target) is **intentionally minimal**:

- Full-width mic button, a small "Done" button, and a standard switch-keyboard globe.
- Tap mic → starts recording (visual pulsing animation, elapsed-time counter).
- Tap again → stops, writes WAV to App Group, posts Darwin notification.
- Shows a "Processing in WhisprLocal…" state with a spinner.
- When the main app writes the result to `outbox/`, keyboard reads and calls `textDocumentProxy.insertText(_:)`.
- If the user switches apps before completion: the result still lands in the App Group; next time the keyboard is active it checks for pending outputs and offers to insert them.
- Falls back gracefully if Full Access is not granted: show a one-time card explaining what Full Access unlocks (nothing is sent over network — it's only needed for App Group access and URL-scheme handoff).

**Strictly do NOT** load any ML models inside the keyboard extension. Its only jobs are: capture audio, serialize, hand off, insert result.

---

## 7. UX & Design

- SwiftUI, dark-mode-first.
- Use SF Symbols throughout. No third-party icon packs.
- Onboarding: 4 screens — welcome, privacy promise, mic permission, model download (user picks from catalog; defaults pre-selected; explicit download size shown before they confirm).
- Settings: Model selection (STT + LLM), Polish prompt templates (editable), Dictionary, Snippets, History, Privacy (clear data, export), About.
- A persistent "offline / on-device" badge in the top bar of the main app — this is a core brand promise, make it visible.
- Accessibility: VoiceOver labels on every interactive element; Dynamic Type support end-to-end; Reduce Motion respected for the waveform.

---

## 8. Privacy & Security Requirements

These are product-defining, not optional.

1. **No network requests at runtime** except: (a) model download from Hugging Face on user-initiated action, (b) model catalog JSON refresh (optional, user-toggleable, disabled by default).
2. Add an **App Transport Security** config that **denies all domains by default** and allow-lists only `huggingface.co` and `cdn-lfs.huggingface.co` for downloads.
3. No analytics. No crash reporting SDK. Use Xcode Organizer + OSLog only.
4. Write a `PRIVACY.md` in the repo and surface it in Settings.
5. All App Group files encrypted at rest by iOS Data Protection — set `NSFileProtectionComplete` attribute on every write.
6. Auto-delete audio WAVs from App Group `inbox/` immediately after transcription. Polished text in `outbox/` deleted after insertion or within 60s, whichever first.
7. Add a "Privacy Audit" debug screen (behind a hidden gesture) that lists every network call made in the session — should always be empty during dictation flows.

---

## 9. Project Structure

```
WhisprLocal/
├── WhisprLocal.xcodeproj
├── WhisprLocalApp/                     # Main iOS app target
│   ├── App/                            # @main, AppDelegate, scene config
│   ├── Features/
│   │   ├── Recording/                  # RecordView, waveform, AudioCaptureService
│   │   ├── Transcription/              # WhisperEngine (WhisperKit wrapper)
│   │   ├── Polish/                     # PolishEngine (MLX wrapper), prompt templates
│   │   ├── CommandMode/
│   │   ├── Dictionary/
│   │   ├── Snippets/
│   │   ├── History/
│   │   ├── Models/                     # ModelCatalog, ModelDownloader
│   │   ├── Settings/
│   │   └── Onboarding/
│   ├── Core/
│   │   ├── AppGroup/                   # SharedContainer, JobQueue, DarwinNotifications
│   │   ├── Audio/                      # AudioFormat conversion (AVAudioConverter → 16kHz)
│   │   ├── Storage/                    # SwiftData models
│   │   └── DI/                         # Lightweight DI container
│   ├── DesignSystem/                   # Colors, typography, reusable components
│   ├── Resources/
│   ├── Tests/                          # Unit tests for main app business logic
│   │   └── Fixtures/                   # Bundled audio samples, mock model responses
│   └── UITests/                        # UI tests (recording, settings, history)
├── WhisprKeyboard/                     # Keyboard extension target
│   ├── KeyboardViewController.swift
│   ├── MicCaptureService.swift         # Strictly bounded, < 48MB
│   └── Resources/
├── Shared/                             # Swift Package, linked by both targets
│   ├── Sources/WhisprShared/
│   │   ├── AppGroupPaths.swift
│   │   ├── JobEnvelope.swift           # Codable job metadata
│   │   ├── DarwinNotificationNames.swift
│   │   └── AudioFormat.swift
│   └── Tests/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── PRIVACY.md
│   ├── MODEL_CATALOG.md
│   └── KEYBOARD_INSTALL.md
└── README.md
```

---

## 10. Testing Requirements

- **Unit tests** for: `AudioFormat` conversion, `JobEnvelope` serialization, `ModelCatalog` device-compatibility filter, prompt template rendering, snippet expansion regex.
- **Integration tests** for: WhisperKit round-trip on a bundled 2-second test WAV (ships as a test resource, creative-commons audio), App Group write/read.
- **UI tests** for: recording flow, settings model picker, history export.
- Target **≥ 70% line coverage** on business logic (exclude UI and WhisperKit/MLX wrapper thin layers from the coverage target).
- Manual test matrix documented in `docs/TEST_MATRIX.md`: iPhone 12 / iPhone 14 / iPhone 15 Pro / iPhone 16 Pro, iOS 17 / iOS 18, English + Hindi + Marathi audio samples.

---

## 11. Milestones (deliver in order, PR per milestone)

Each milestone ends with a working build and updated docs.

**M0 — Skeleton** (day 1)
Xcode project with two targets, App Group entitlement, shared Swift package, CI-ready (GitHub Actions workflow file building on macOS runner), empty SwiftUI shell, placeholder keyboard.

**M1 — Audio capture** (days 2–3)
AVAudioEngine mic capture in main app, 16kHz Float32 conversion, waveform UI, WAV write, permissions flow.

**M2 — WhisperKit integration** (days 4–5)
Model catalog JSON, model downloader with progress UI, `WhisperEngine` wrapper, first working transcription end-to-end in main app.

**M3 — MLX polish** (days 6–7)
MLX Swift integration, default Qwen 2.5 1.5B, polish prompt templates, side-by-side raw/polished view.

**M4 — Keyboard extension** (days 8–10)
KeyboardViewController with mic button, App Group hand-off, Darwin notifications, URL-scheme wake-up of main app, result insertion via `textDocumentProxy`.

**M5 — Command Mode + Dictionary + Snippets** (days 11–12)
Command Mode flow, prompt injection of dictionary into Whisper, snippet expansion pre-pass.

**M6 — History + Settings + Onboarding polish** (days 13–14)
SwiftData history, all settings screens, 4-screen onboarding, accessibility pass, Dynamic Type pass.

**M7 — Hardening** (day 15)
Privacy Audit screen, ATS lockdown, crash-free launch test, memory profile of keyboard extension (must stay < 40 MB with headroom), test matrix execution.

Do **not** collapse milestones. Ship each as its own PR with a demo GIF in the description.

---

## 12. Things You Must NOT Do

- Do not add cloud fallback. No OpenAI, no Anthropic, no Google Cloud. Not even a "optional for better quality" toggle.
- Do not ship any analytics, telemetry, or third-party SDKs.
- Do not load LLM or Whisper models inside the keyboard extension.
- Do not persist audio beyond the job lifecycle.
- Do not hardcode any single model as the only option — the catalog is the contract.
- Do not exceed the iOS 17 minimum without asking.
- Do not add a "share to X" feature, sign-in, or account system.

---

## 13. Repository Hygiene

- Commits follow Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`).
- Branches: `main` is protected; work on `milestone/M<number>-<slug>` branches.
- PR template includes: summary, screenshots/GIF, test plan, risk assessment, checklist of spec items addressed.
- Add a `CONTRIBUTING.md` and `.editorconfig`.
- SwiftLint config at repo root; enforce in CI.
- License: MIT (matches WhisperKit and MLX Swift).
- README.md covers: what it is, why local, how to build, how to install the keyboard, model catalog, privacy promise.

---

## 14. First Actions — Start here

1. Confirm you've read this spec and list any clarifying questions. If none, say "No questions — starting M0."
2. Create the Xcode project exactly per §9.
3. Open a PR titled `feat(m0): project skeleton with app + keyboard targets`.
4. In the PR description, paste a rendered version of the architecture diagram from §2 (ASCII is fine; Mermaid is better).
5. Push `docs/ARCHITECTURE.md` and `docs/PRIVACY.md` as part of M0.
6. Stop after M0 and wait for my review before starting M1.

---

## 15. Anti-Drift Reminders (Codex, re-read before each milestone)

- The two differentiators are **local-only** and **model-pluggable**. Every design decision is measured against these.
- The keyboard extension is dumb by design. Resist the urge to make it smarter.
- When in doubt about scope, cut. Ship less, ship working.
- Every feature flag that changes privacy posture (e.g., catalog refresh) defaults to OFF.

End of spec.
