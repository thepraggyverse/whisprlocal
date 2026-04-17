# Test matrix

Device × OS × language combinations WhisprLocal is verified against before
each release.

> **Status: stub.** This document is populated at **M7** (hardening, test
> matrix execution). At M0 we have a smoke test (app launch) and unit
> tests for `JobEnvelope` + `AudioFormat`. The real matrix starts
> mattering at M2 when transcription runs end-to-end on real audio.

## Planned coverage (per `PROJECT_SPEC.md` §10)

### Devices

| Device | Chip | RAM | Minimum iOS | Status |
|---|---|---|---|---|
| iPhone 12 | A14 | 4 GB | 17.0 | — |
| iPhone 14 | A15 | 6 GB | 17.0 | — |
| iPhone 15 Pro | A17 Pro | 8 GB | 17.0 | — |
| iPhone 16 Pro | A18 Pro | 8 GB | 18.0 | — |

Simulator runs on iPhone 17 Pro (see `CLAUDE.md` build commands footnote
for the Pro-tier rationale).

### iOS versions

- iOS 17.x (minimum deployment target)
- iOS 18.x
- iOS 26.x (current at time of M0)

### Languages

The multilingual default (`whisper-base`) covers English, Hindi, and
Marathi — the three the author tests against. Other languages are
supported via larger model variants (`whisper-small`, `whisper-large-v3-turbo`).

### What gets tested per cell

- **Recording** — tap-and-hold and toggle modes both start/stop capture cleanly.
- **Transcription accuracy** — qualitative review of 3 CC-licensed test
  WAVs per language. Not a WER benchmark; a sanity pass.
- **Polish quality** — same 3 WAVs run through default + email + message
  templates, qualitative review.
- **Keyboard hand-off** — keyboard → App Group → main app → back to
  keyboard → `insertText` all in under 5 s wall-clock.
- **Memory** — keyboard stays under 40 MB (headroom below the 48 MB
  ceiling) across a 10-minute continuous use session.
- **Privacy** — Privacy Audit screen shows empty network calls log
  throughout.

## How to run the matrix

Forthcoming at M7. The intent is a single checklist per device/OS cell,
manual execution with screenshots, results committed to this document.

## Opt-in integration tests

Some tests in `WhisprLocalApp/Tests/` download real weights and run real
Core ML inference. They are **skipped in default CI** because they need
network (a ~40 MB download on first run), a warm Core ML cache, and a
real iOS Simulator device. Run them manually when you want to verify the
ADR-002 mitigations against real weights, or before shipping a milestone
that touched `WhisperEngine`.

### `WhisperEngineIntegrationTests` — M2

Gated on the `WHISPR_INTEGRATION=1` environment variable. Runs the
tiny English Whisper variant (`openai_whisper-tiny.en`) against a
procedurally-generated 2 s silent WAV that matches the M1 capture
format (16 kHz Float32 mono). Does not assert a transcript — absence
of crash on iOS 26 is the contract.

```bash
WHISPR_INTEGRATION=1 xcodebuild test \
  -scheme WhisprLocalApp \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
  -only-testing:WhisprLocalAppTests/WhisperEngineIntegrationTests
```

A real CC-licensed speech fixture (so the test can also assert a
transcript string contains something) lands in M7 hardening per
spec §10.
