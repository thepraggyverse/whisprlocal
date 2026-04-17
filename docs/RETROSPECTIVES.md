# Milestone Retrospectives

Append-only log of what went well, what surprised, and one specific lesson per milestone.

## M0 — Project skeleton (shipped 2026-04-17, v0.1.0-m0 @ 2add398)

What went well: the plan-before-code-before-commit cadence kept every failure local. The Step 5a MLX/WhisperKit discovery pass caught that `mlx-swift-examples` no longer exports `MLXLLM` — exactly the kind of assumption that would have produced a load-bearing bug at M3 if pinned blindly at M0. Gate 4.5's link-surface check proved the keyboard architecture holds by construction, not by convention.

Surprises: entitlements files got silently clobbered when xcodegen's `entitlements:` key lacked inline `properties:` — a five-minute recovery but unexpected. The iPhone 16 Pro → iPhone 17 Pro drift was a sharper reminder that "latest" means different things to different Xcode installs. CI caught the `rg`-not-on-macos-15 gap I should have predicted at the workflow-authoring moment.

For M1: verify tool availability on the target environment before writing the code that depends on it — check `gh api repos/actions/runner-images/contents/images/macos` (or equivalent) the first time I reach for any CLI tool in CI, not after the red X.

Post-CI-green bug caught via simulator verification: `CaptureError` code 2 on record tap. Root cause: `CODE_SIGNING_ALLOWED: NO` in Debug stripped the App Group entitlement from the binary. CI didn't catch it because tests stubbed the inbox URL provider. Fix: re-enable signing on Debug (simulator uses free ad-hoc identity), add regression test that asserts `AppGroupPaths.containerURL` is non-nil, add CI step that greps the binary for the entitlement, codify in CLAUDE.md anti-patterns.

Lesson: "green CI" is necessary but not sufficient. The simulator verification gate exists precisely for entitlement/runtime-config bugs that test suites (by their nature) mock away. This case validates the "PR stays draft until human verifies on simulator" rule from Mode 2.

### Lessons codified back into project rules
- [x] Add to CLAUDE.md anti-patterns: "Do not use xcodegen `entitlements:` key without inline `properties:` — silently clobbers hand-written entitlements files. Use `CODE_SIGN_ENTITLEMENTS` build setting to reference them instead." — applied at M1 kickoff.
- [x] Add to CLAUDE.md session workflow: "Before writing CI code that depends on a CLI tool, verify the tool is preinstalled on the target runner image (check the macos-15 image manifest at github.com/actions/runner-images)." — applied at M1 kickoff.
- [x] Add to CLAUDE.md build commands: "Sim destination uses `OS=latest,name=iPhone <N> Pro` where N is the highest Pro tier shipped with the installed Xcode." — was already present in CLAUDE.md during M0 (lines 63-69); no new edit needed.

## M1 — Audio capture (shipped 2026-04-17, branch `milestone/M1-audio`)

What went well: the commit-sequence plan held up end-to-end — every commit compiled and tested in isolation, and each `/verify` loop caught one real issue (the file-protection simulator-vs-device gap) exactly where it was cheapest to fix. Splitting WAVWriter and AudioConverter into two small files made the engine-tap closure in AudioCaptureService boring — it literally just wires references together, which is what code on the audio I/O thread should look like. Delegating RIFF/WAVE header correctness to `AVAudioFile` dodged a whole class of IEEE-float-vs-PCM header bugs that would have been silent on the test WAVs and loud on the first real WhisperKit invocation at M2.

Surprises: iOS simulator does not honor `NSFileProtectionComplete` — `attributesOfItem` returns `nil` for `.protectionKey` because the sim is running on macOS, which doesn't implement iOS Data Protection. The fix was simple (tolerate `nil` on simulator, assert `.complete` on device), but the failure mode was "your privacy invariant is invisible in tests" — exactly the kind of thing to surface in PRIVACY.md. The second surprise: the M0 `AudioFormat.swift` docstring had already been partly wrong (it claimed the keyboard did the conversion) — caught it during commit 2 before building on the misconception. Always read scaffolding the previous milestone left you before reusing it.

For M2: Apple's simulator gaps around privacy attributes are a systematic testability hole, not a one-off. When M2 adds HF model downloads, assume the sim will not enforce ATS exactly the way the device does either — plan a manual device verification step into the milestone, not just CI.

### Lessons codified back into project rules
- [ ] Add to docs/PRIVACY.md (near file-protection paragraph): "simulator tolerance is expected; device-strict assertions live in the test suite." — applied in this commit.
- [ ] Add to CLAUDE.md anti-patterns: "Do not assume iOS Data Protection, ATS, or keychain behavior on the simulator matches device. Privacy-invariant tests should be simulator-tolerant with a device-strict branch." — propose as a follow-up for M2 planning rather than rushing here.
