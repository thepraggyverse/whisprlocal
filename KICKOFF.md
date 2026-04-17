# Kickoff Prompt for Claude Code — WhisprLocal iOS App

> Paste the block below into a **fresh Claude Code session** at the root of an empty directory (`cd ~/dev && mkdir WhisprLocal && cd WhisprLocal && claude`). This is your one-time bootstrap message. After this, use the slash commands in `.claude/commands/` and the `CLAUDE.md` for ongoing work.

---

## Paste this into Claude Code:

```
You are the lead iOS engineer on a new project called **WhisprLocal** — a fully on-device voice-to-text iOS app with a companion custom keyboard, modeled on Wispr Flow / Recast / Ghostpepper but with zero cloud dependencies.

Before writing any code, do the following in order. Stop and wait for my confirmation after each numbered step.

1. Read the full project spec at `PROJECT_SPEC.md` (I will paste it in next message if the file doesn't exist yet). Summarize the five most important constraints in your own words so I know you've understood them.

2. Propose the initial repository layout as a file tree. Do not create files yet. Call out any deviations from the layout specified in the spec and justify them.

3. Create `CLAUDE.md` at the repo root with: project overview, build commands, test commands, code style rules, and anti-patterns to avoid. This is the file you'll auto-load every session — make it dense and high-signal, no fluff.

4. Create `.claude/commands/` with the following custom slash commands as separate .md files:
   - `/plan-milestone` — produces a detailed plan for a given milestone before any coding starts
   - `/verify` — runs build + tests, reports results, does not proceed on failure
   - `/audit-privacy` — greps the codebase for forbidden patterns (URLSession to non-allowlisted domains, analytics SDKs, telemetry)
   - `/memory-check` — estimates the keyboard extension's memory footprint and flags anything likely to blow the 48MB ceiling
   - `/spec-check` — re-reads PROJECT_SPEC.md and flags any drift in recent changes

5. Create an Xcode project scaffold for milestone M0 per the spec's §9 file layout. Use `xcodegen` (install via Homebrew if not present) driven by a `project.yml` so the project file is regeneratable and diff-friendly. Two targets: `WhisprLocalApp` (iOS app, min iOS 17.0) and `WhisprKeyboard` (Custom Keyboard Extension). Add App Group entitlement `group.com.praggy.whisprlocal` to both. Add the `com.apple.developer.kernel.increased-memory-limit` entitlement to the app target only.

6. Add a `Shared` Swift Package linked by both targets, containing `AppGroupPaths`, `JobEnvelope`, `DarwinNotificationNames`, `AudioFormat` stubs.

7. Add Swift Package dependencies:
   - WhisperKit (pin to a specific version, check the latest stable tag)
   - MLX Swift Examples (pin)

8. Add SwiftLint config and a GitHub Actions workflow that runs `xcodebuild build` + tests on macOS runner.

9. Write `docs/ARCHITECTURE.md` with the Mermaid diagram from the spec's §2, and `docs/PRIVACY.md` per §8.

10. Commit everything using Conventional Commits. Open a draft PR titled `feat(m0): project skeleton with app + keyboard targets` with a body that includes: the rendered architecture diagram, a checklist of what landed vs. what's pending for M0, and the build output from `xcodebuild`.

11. Stop. Report back with (a) the PR link or branch name, (b) the build output's last 40 lines, (c) any clarifying questions before we move to M1 (audio capture).

Operating rules throughout this entire project — re-read these every session:

- Plan before you code. Every non-trivial change starts with a numbered plan you post in chat, then I approve.
- Small commits. Every commit compiles. If it doesn't, fix it before moving on.
- Run `/verify` after every logical chunk. Don't move to the next task with a red build.
- Never add a feature not in PROJECT_SPEC.md without asking.
- Never add a cloud dependency. Ever. If you're tempted to, stop and ask why — the answer is almost certainly "don't."
- Never load ML models in the keyboard extension. The 48MB ceiling is the hard constraint that shapes the whole architecture.
- When you're uncertain, ask. Do not guess APIs — read the actual package docs or source.
- Respect the milestone sequence. Do not start M(n+1) until M(n) is merged.

Start with step 1. Wait for me to paste the spec.
```

---

## What to do after pasting

1. Claude Code will ask for `PROJECT_SPEC.md`. Paste the contents of the separate `PROJECT_SPEC.md` file (same content as the Codex spec, renamed).
2. Review its summary in step 1. If it misunderstood anything, correct it before moving on.
3. Approve the file tree from step 2 or redirect.
4. Let it run through steps 3–10 autonomously — it will stop at step 11 for your review.
5. Open the PR, skim the diff, merge to `main`, then use `/plan-milestone M1` to start audio capture.

## Session hygiene tips (Mumbai-time reality check)

- **Name your sessions.** `claude --name whisprlocal-m0` so you can `claude --resume whisprlocal-m0` tomorrow.
- **Use plan mode for anything risky.** `Shift+Tab` twice to enter plan mode when about to refactor something load-bearing.
- **`/compact` before long context fills.** Tell it what to preserve: "compact but preserve the milestone status and the list of modified files."
- **Run `/audit-privacy` at the end of every milestone.** The privacy promise is the product — don't let it rot.
- **Opus for architecture, Sonnet for grinding.** Flip with `/model` when you want cheaper execution on well-specified tasks.
