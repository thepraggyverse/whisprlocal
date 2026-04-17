# WhisprLocal — Claude Code Scaffold

This folder contains everything you need to bootstrap the **WhisprLocal** iOS project with Claude Code. It's structured the way Claude Code expects: a `CLAUDE.md` at the root (auto-loaded every session), a `PROJECT_SPEC.md` for deep context, and custom slash commands in `.claude/commands/`.

## What's in this bundle

```
cc/
├── KICKOFF.md                        ← One-time bootstrap prompt (paste into fresh session)
├── CLAUDE.md                         ← Always-loaded project memory
├── PROJECT_SPEC.md                   ← Full spec (source of truth)
└── .claude/
    └── commands/
        ├── plan-milestone.md         ← /plan-milestone M1
        ├── verify.md                 ← /verify
        ├── audit-privacy.md          ← /audit-privacy
        ├── memory-check.md           ← /memory-check
        └── spec-check.md             ← /spec-check
```

## How to use this

### 1. Set up the project directory

```bash
mkdir -p ~/dev/WhisprLocal && cd ~/dev/WhisprLocal
# Copy this scaffold in
cp -r /path/to/this/bundle/* .
cp -r /path/to/this/bundle/.claude .
# Initialize git
git init && git add -A && git commit -m "chore: bootstrap project scaffold"
```

### 2. Launch Claude Code with a named session

```bash
claude --name whisprlocal-m0
```

### 3. Paste the kickoff prompt

Open `KICKOFF.md`, copy the block inside the triple backticks, paste it into Claude Code. It will read `CLAUDE.md` + `PROJECT_SPEC.md` automatically and start executing the M0 bootstrap (Xcode scaffold, CI, docs, first PR).

### 4. Use slash commands for the rest of the project

| When | Command |
|---|---|
| Starting a new milestone | `/plan-milestone M<n>` — get a plan, approve, let it execute |
| After any logical chunk of changes | `/verify` — lint + build + test, stops on failure |
| End of every milestone | `/audit-privacy` — greps for forbidden patterns |
| After any edit to `WhisprKeyboard/` | `/memory-check` — flags 48MB risk |
| Before every PR merge to `main` | `/spec-check` — flags drift from PROJECT_SPEC |

### 5. Resume sessions by name

```bash
claude --resume whisprlocal-m0
# or
claude --resume whisprlocal-m2-whisperkit
```

Name each session after the milestone you're working on so you can jump back in without losing context.

## Why this structure vs. just pasting a big prompt

- **`CLAUDE.md` auto-loads every session.** No copy-paste, no reminders needed. This is where the 5 non-negotiables live so they never drift.
- **`PROJECT_SPEC.md` is loaded on demand** by `/spec-check` and when Claude needs deep context. Keeps the always-on context lean.
- **Slash commands enforce workflow.** `/verify` after every chunk prevents silent red builds. `/audit-privacy` prevents silent privacy regressions.
- **The KICKOFF is one-shot.** After it runs M0, you never need it again. Ongoing work is driven by `/plan-milestone`.

This is the "paved path" for this project — Anthropic's own Claude Code team recommends exactly this layout (CLAUDE.md + slash commands + spec file) for non-trivial projects ([source](https://anthropic.com/engineering/claude-code-best-practices)).

## Differences from the Codex version

| | Codex | Claude Code |
|---|---|---|
| Delivery | Single pasted prompt | Bootstrap + persistent scaffold |
| Context | Prompt only | `CLAUDE.md` auto-loaded every session |
| Workflow enforcement | Instructions in the prompt | Slash commands (`/verify`, `/audit-privacy`) |
| Iteration | Re-prompt for changes | Resume session, use slash commands |
| Drift control | Manual re-reading of spec | `/spec-check` command |
| Memory ceiling checks | Described in prompt | `/memory-check` executable command |

Same spec, same product, same constraints — different ergonomics.

## First session — what to expect

1. You paste the kickoff prompt from `KICKOFF.md`.
2. Claude Code asks to read `PROJECT_SPEC.md`. It does. It summarizes the 5 constraints back to you.
3. You approve or correct the summary.
4. It proposes a file tree. You approve.
5. It runs through steps 3–10 of the kickoff — creates Xcode project via `xcodegen`, adds SPM deps, writes docs, opens a draft PR for M0.
6. It stops at step 11. You review the PR, merge it, then `/plan-milestone M1`.

Expect the M0 session to take 20–40 minutes of wall-clock time. M1–M3 are the meat of the build. M4 (keyboard extension + IPC) is the trickiest and where `/memory-check` earns its keep.

## Troubleshooting

- **Claude Code is doing work without a plan.** Stop it. Remind it of the `CLAUDE.md` rule: "Plan before you code." Or explicitly invoke `/plan-milestone`.
- **Context is getting full.** Run `/compact focus on: current milestone, modified files, open questions`.
- **It's about to add a cloud SDK.** This should never happen given the anti-patterns in `CLAUDE.md`. If it does, refuse and file a bug against the CLAUDE.md — something in it isn't landing.
- **Privacy audit is failing.** Do not merge. Fix the violation or escalate it to me to discuss whether the spec needs to change.
