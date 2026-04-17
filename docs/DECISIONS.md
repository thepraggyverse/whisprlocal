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
