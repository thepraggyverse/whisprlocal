# Architecture Decision Records

A chronological log of architecturally-significant decisions made on
WhisprLocal. Each entry captures the context at the time of the decision,
the decision itself, and the consequences — so future contributors (and
future-us) don't re-litigate settled questions.

New ADRs are appended to the bottom of this file, numbered sequentially.
Once accepted, an ADR is historical — it is not edited except to mark it
**Superseded by ADR-NNN** if a later decision overrides it.

---

## ADR-001: Defer WhisperKit and MLX pinning to usage milestones

**Status:** Accepted (2026-04-17)

**Context**

Step 5a discovery ahead of M0 revealed two findings that affected both
third-party dependencies the spec calls for:

1. **mlx-swift-examples 2.29.1** (latest stable) no longer exports
   `MLXLLM` or `MLXLMCommon` as SwiftPM library products. The current
   `Package.swift` declares only `MLXMNIST` and `StableDiffusion`. LLM
   targets appear to have moved into the repo's `Applications/` /
   `Tools/` tree as example apps rather than linkable libraries.
   Consequence: the spec's reference to MLX Swift Examples as our LLM
   backend cannot be honored at the latest version without either pinning
   to an older tag or vendoring source.

2. **WhisperKit v0.18.0** (latest stable, 2026-04-01) has two open issues
   affecting our target platform:
   - `#392` — `SuppressTokensFilter writes to read-only MLMultiArray on
     iOS 26`. Open. Workaround: set `supressTokens: []` to bypass.
   - `#315` — Swift 6 crash in `prewarmModels()`. Open. Workaround:
     compile under Swift 5 language mode (which we do anyway —
     `SWIFT_VERSION = 5.10` in `project.yml`).
   Both are manageable but unresolved.

Landing either dependency in the M0 `project.yml` would commit us to a
decision that doesn't need to be made until the dependency is actually
used (WhisperKit at M2, MLX at M3), and the MLX question in particular
needs dedicated discovery that wasn't scoped into M0.

**Decision**

`project.yml` at M0 declares only the local `WhisprShared` Swift Package
as a SPM dependency. WhisperKit gets pinned during M2 against real
transcription code. The MLX LLM strategy gets decided during M3 after
dedicated research into:

- The last mlx-swift-examples tag that exported `MLXLLM` (pinning
  to that tag, trading off missed model support and bug fixes).
- The current state of `LocalLLMClient` (mentioned in spec §3 as a
  feature-flagged fallback — may warrant promotion to primary).
- Any standalone MLX-LLM Swift package that emerged since our spec was
  written.
- Vendoring `MLXLLM` source directly into WhisprLocal.

**Consequences**

- M0 ships lean and fast. The Xcode project, CI run, and build matrix
  all avoid resolving two large upstream trees that M0 code can't yet
  exercise.
- The architectural contract — `WhisprKeyboard` never links ML
  frameworks — is preserved **by construction** at M0: there are no ML
  frameworks in the dependency graph at all.
- At the start of M2, we must re-verify WhisperKit's latest stable
  status, the state of `#392` and `#315`, and pick an exact-version
  pin. If those issues remain open, the feature flag
  `kWorkaroundWhisperKit392` lands alongside `WhisperEngine` with a
  code comment linking to the issue and a `TODO` to revert when upstream
  ships a fix.
- Before M3, we spend a dedicated 1–2 hours re-researching the MLX
  landscape, then pick a path and document the rationale in a new ADR.
- The aspirational regex guards in `.claude/commands/audit-privacy.md`
  and `.claude/commands/memory-check.md` that mention `MLXLLM`,
  `MLXLMCommon`, `MLXNN`, `MLXRandom`, etc. are **correct as-is** —
  they catch imports that don't exist yet, which is the right posture
  for an architectural guard.
- If a future reader wonders "why didn't M0 include the big deps?" —
  this ADR is the answer.

**Alternatives considered**

- *Pin WhisperKit at M0 with deferred MLX* — rejected because landing
  WhisperKit without a usage site means carrying known-issue risk
  without validation. We want verification to happen at the site of
  use, not the site of declaration.
- *Pin MLX to an older tag (2.24.x or earlier) that still exported
  MLXLLM* — rejected because it commits us to a specific MLX strategy
  under time pressure with incomplete information. Better done
  deliberately at M3.
- *Pin MLX by vendoring Libraries/MLXLLM source directly* — rejected
  for M0 scope. Revisit at M3.

---

## ADR-002: Pin WhisperKit via argmax-oss-swift @ 0.18.0, product WhisperKit only

**Status:** Accepted (2026-04-17)

**Context**

`PROJECT_SPEC.md` §3 originally pointed at `github.com/argmaxinc/WhisperKit`.
During M2 discovery we confirmed that Argmax renamed and restructured the
package in March 2026: the canonical repo is now
`github.com/argmaxinc/argmax-oss-swift`, and what was once a single
`WhisperKit` package is now a multi-kit umbrella exposing four separate
library products — `WhisperKit`, `TTSKit`, `SpeakerKit`, and the
all-in-one `ArgmaxOSS`. The old URL still redirects, but the package name
resolved by SPM is `argmax-oss-swift`, not `WhisperKit`. ADR-001 deferred
this pin decision to M2 precisely so we could make it against the current
state of upstream rather than at the spec-writing time.

Discovery also confirmed two open upstream issues that affect our target
runtime, both documented in ADR-001 and re-verified in M2:

- `#392` — `SuppressTokensFilter` writes to a read-only `MLMultiArray` on
  iOS 26 when `suppressTokens` includes `-1`. Still open.
- `#315` — Swift 6 crash during `prewarmModels()`. Still open.
- `#408` — SwiftPM dependency-scan warnings on Xcode 26.2
  (`WhisperKit missing dependency on Tokenizers/Hub/...`). Warnings only,
  no runtime impact. Documented here so future triage doesn't treat the
  noise as a regression.

**Decision**

1. Declare the package as `ArgmaxOSS` in `project.yml` with URL
   `https://github.com/argmaxinc/argmax-oss-swift` and
   `exactVersion: 0.18.0`. We pin exact, not `upToNextMinor`, because
   minor bumps in this package have introduced API shifts (v0.15
   `TranscriptionResult` struct → class) and structural target
   additions (v0.17/0.18 SpeakerKit + ModelManager refactor). Every
   bump gets a deliberate, reviewed PR.
2. Depend on the `WhisperKit` product only — **not** the `ArgmaxOSS`
   umbrella, **not** `TTSKit`, **not** `SpeakerKit`. We don't ship
   text-to-speech or speaker diarization, so linking those products
   only adds binary size and open-issue exposure.
3. Use the canonical `argmax-oss-swift` URL explicitly. The old URL's
   redirect is reliable today but is an implementation detail we
   shouldn't depend on; future SwiftPM resolver changes could surface
   the redirect as a warning or failure.
4. Update `PROJECT_SPEC.md` §3 to reflect the canonical URL.

**Consequences**

- Smaller binary and tighter dependency graph: no TTSKit / SpeakerKit
  transitive Core ML baggage. The Core ML framework links implicitly
  through WhisperKit itself, not through the umbrella.
- Version bumps are intentional events, not resolver side-effects. A
  future `v0.19.0` arrives as a PR titled "bump WhisperKit" with a
  discovery pass on its release notes, not silently.
- The known-issue mitigations (ADR-001 → ADR-002 continuity) land at the
  call sites they affect rather than as build-level patches. In-code
  references:
    - `WhisprLocalApp/Features/Transcription/WhisperEngine.swift` always
      constructs `DecodingOptions(suppressTokens: [])` and carries an
      inline comment linking to `argmax-oss-swift#392`.
    - `WhisperEngine` never calls `prewarmModels()`; lazy-load on first
      `transcribe()` is the intended path. Inline comment links to
      `argmax-oss-swift#315`.
    - `project.yml` sets `SWIFT_VERSION: "5.10"` — not defaulted — so the
      `#315` mitigation survives any future Xcode default change.
- CI noise: on Xcode 26.2 we'll see SwiftPM dependency-scan warnings
  from `#408`. Warnings only. Do not treat as errors. Our CI currently
  runs Xcode 16, so the warnings are local-dev-only today.
- Future `prompt`-field injection (our Dictionary feature in M5) passes
  through `DecodingOptions.prompt`, which is unrelated to
  `suppressTokens` and unaffected by `#392`.

**Revisit when**

- A new minor version lands (v0.19+). Re-run the M2-style discovery
  (release notes, open-issue scan for our target OSes) and bump
  deliberately.
- Either `#392` or `#315` closes — re-evaluate the corresponding
  mitigation. The `suppressTokens: []` workaround has no downside for
  our use case (we don't need the WhisperKit default suppression token
  set), but `prewarmModels()` would reduce cold-start latency by 1–2s
  if we could call it safely.
- Product scope grows to include text-to-speech (promote `TTSKit`
  product) or speaker diarization (promote `SpeakerKit`). Either
  requires its own ADR because both bring non-trivial transitive deps
  and their own open-issue surface.
- A future Xcode release makes `#408` warnings fail the build — pin the
  Xcode version in CI or add explicit target dependencies if upstream
  hasn't fixed it.

**Alternatives considered**

- *Use the `ArgmaxOSS` umbrella product* — rejected. Pulls in TTSKit
  and SpeakerKit, neither of which we ship. Adds binary weight and
  open-issue exposure with no benefit.
- *Pin `.upToNextMinor(from: "0.18.0")`* — rejected. Upstream's recent
  minor bumps are not SemVer-pure (struct → class API change in v0.15;
  new top-level targets in v0.17/0.18). Exact pinning forces every bump
  through review.
- *Keep the old `argmaxinc/WhisperKit` URL and rely on the redirect* —
  rejected. The redirect works today but depending on it is fragile.
  Canonical name is cheap correctness.
