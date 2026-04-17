# Privacy posture

WhisprLocal is designed so that your voice and the text we produce from it
never leave your iPhone. This document lists the commitments we make and
how each one is enforced in code.

The full rationale is in `PROJECT_SPEC.md` §8. This page is the user-facing
summary and the engineering contract.

## The seven commitments

1. **No network requests at runtime except user-initiated model downloads.**
   The only outbound traffic the app is allowed to make is fetching model
   weights from `huggingface.co`, and only when you explicitly tap "Download
   model" in Settings. Nothing happens in the background, on launch, or
   during dictation.

2. **App Transport Security denies all domains by default.** Our
   `Info.plist` sets `NSAllowsArbitraryLoads: false` and allow-lists only
   `huggingface.co` and `cdn-lfs.huggingface.co` under `NSExceptionDomains`.
   Every other domain is blocked at the OS layer — no code path in the app
   can reach them.

3. **No analytics, no telemetry, no crash reporting SDKs.** Not Mixpanel,
   Segment, Firebase, Sentry, Amplitude, PostHog, Bugsnag, Crashlytics,
   Datadog, Adjust, AppsFlyer, or Branch. Diagnostics come from `OSLog` and
   show up only in the Xcode Organizer — they never leave your device. CI
   enforces this with a build-time grep (`/audit-privacy`) that fails the
   build if any such import appears in the source.

4. **Audio is transient. Nothing is persisted.** WAV files written to the
   App Group `inbox/` are deleted as soon as transcription completes.
   Polished text written to `outbox/` is deleted after insertion, or within
   60 seconds — whichever comes first. History (on-device, SwiftData only)
   stores the text of past sessions if you turn it on; the audio is never
   kept.

5. **App Group files are encrypted at rest.** Every write to the shared
   container sets the `NSFileProtectionComplete` attribute, meaning the
   file is readable only while your device is unlocked — iOS encrypts it
   with a key derived from your passcode.

6. **Nothing syncs, anywhere.** There is no iCloud sync, no "backup my
   history", no account system, no sign-in. If you delete the app, the
   data is gone.

7. **A Privacy Audit screen proves the above.** Settings → Privacy Audit
   shows every network call made in the current session (should always be
   empty during dictation) and lets you browse the App Group container to
   confirm no audio or polished text is lingering.

## How this is enforced

- **ATS config** — `project.yml` declares `NSAppTransportSecurity` with the
  `huggingface.co` + `cdn-lfs.huggingface.co` exception domains. Anything
  else the code tries to reach fails at the URLSession layer. Hand-verified
  at every milestone via `/audit-privacy`.
- **Build-time grep** — `/audit-privacy` (dev) and the CI workflow (shared
  regex logic) scan for: forbidden SDK imports, `URLSession`/`URLRequest`
  usage outside `ModelDownloader`, ML imports inside `WhisprKeyboard/`,
  and `UIPasteboard` reads/writes in the keyboard. Any hit fails the gate.
- **File-protection attribute** — every write to `App Group/inbox/` sets
  `FileProtectionType.complete` via `FileManager.setAttributes`. Enforced
  at M1 by `AudioCaptureService.stop()` and `WAVWriter.write(_:to:)`, and
  verified by `WAVWriterTests.testFileProtectionComplete` (assertion is
  device-strict, simulator-tolerant since iOS Data Protection is not
  enforced on the macOS-backed simulator).
- **Auto-deletion** — the transcription pipeline deletes the inbox WAV
  before returning. The keyboard deletes the outbox TXT after calling
  `insertText(_:)` or after a 60 s timer, whichever fires first. As of
  M1 the WAVs remain in `inbox/` until M2's WhisperEngine consumes them;
  this is an intentional in-flight state, not a leak.

## What we do not do

- **No cloud fallback.** Not OpenAI, not Anthropic, not Google, not Azure
  — not "optional for better quality" and not behind a feature flag. The
  product stops being WhisprLocal the moment a prompt crosses the network.
- **No share-to-external-service.** There is no "share your transcript to
  X" button. If you want your transcript somewhere else, copy it yourself.
- **No account, no sign-in.** Ever.
- **No "send diagnostic" dialog after a crash.** We'd rather you file an
  issue with steps to reproduce than auto-send anything.

If you find a behavior inconsistent with this page, that is a bug. Please
open an issue.
