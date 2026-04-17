Deliberate-deferral log. Each section: Status, Context, Tradeoff, Revisit when.

## Multi-engine STT support
Status: DEFERRED to v1.1+
Context: v1.0 ships Whisper-only (4 variants). Competitors (Ghost Pepper, etc.) offer Parakeet v3 and Qwen-ASR 0.6B alternatives.
Tradeoff: 3x test matrix; distracts from core Whisper+LLM polish positioning; marginal accuracy gains.
Revisit when: 1000+ users AND non-Whisper is top feature request.

## Manual language override
Status: DEFERRED to M6 or later.
Context: Whisper auto-detects correctly ~95%+ of time on multilingual models. tiny.en is English-only.
Tradeoff: persisted setting + per-model validation; low complexity but non-trivial QA.
Revisit when: multiple user complaints about wrong auto-detect.

## Custom model URL import
Status: DEFERRED, indefinite.
Context: Power-user ability to load fine-tuned Whisper via URL or local path.
Tradeoff: conflicts with curated catalog; trust risk (malicious model); power users can build from source.
Revisit when: open source contributors request it.

## iCloud transcript sync
Status: DEFERRED, requires ADR first.
Context: History tab (M6) stores transcripts locally in SwiftData. Multi-device users may want sync.
Tradeoff: contradicts "100% local" positioning even if CloudKit is Apple-managed.
Revisit when: demonstrated user demand + explicit ADR.

## Model delete button in Settings
Status: DEFERRED to M6 (Settings polish).
Context: downloaded models can only be switched, not removed. Users with full drives need manual cleanup.
Tradeoff: small feature gap.
Revisit when: M6 rolls around.

## Real-device audio capture bug (iPhone 17 Pro Max, iOS 26.4, WhisperKit 0.18)
Status: DEFERRED to M4 (keyboard forces device testing) or M7 (launch prep).
Context: live-mic recordings on real device return empty transcripts in ~20ms. Voice Memos on same device works. Three code-level validations (unit, integration, injection tests) prove pipeline is correct.
Tradeoff: blocks real-device live-mic UX but not M3/M5/M6 development. Simulator + WAV injection testing is sufficient for those.
Fix path: fix/m2-audio-diagnostics branch (commit 2960c2d) has full instrumentation. Triage table in M2 session notes.
Revisit when: M4 kickoff.
