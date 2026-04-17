---
description: Produce a detailed plan for a given milestone before any coding starts
---

Produce a detailed plan for milestone **$ARGUMENTS** of WhisprLocal.

Read `PROJECT_SPEC.md` §11 to get the milestone's scope, then produce:

1. **Prerequisites** — what must be true before starting (green build on previous milestone, merged PR, etc.)
2. **File-by-file change list** — every file you'll create or modify, with one-sentence justification for each
3. **New dependencies** — any SPM additions (should be rare; almost always the answer is "none")
4. **Risks & unknowns** — API surfaces you need to verify, platform quirks, memory concerns
5. **Test plan** — unit tests + manual verification steps
6. **Commit sequence** — ordered list of commits, each compilable on its own
7. **Definition of done** — concrete, testable criteria

Do NOT write code yet. After I approve the plan, you'll execute it commit-by-commit, running `/verify` after each one.

If the milestone touches `WhisprKeyboard/`, include a memory-budget estimate in the Risks section and commit to running `/memory-check` before the PR.

If the milestone touches network code, model downloading, or file writing, include a privacy-impact note and commit to running `/audit-privacy` before the PR.
