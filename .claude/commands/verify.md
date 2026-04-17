---
description: Run build + tests, report results, block progress on failure
---

Run the full verification suite and report results. Do NOT continue with other work if anything fails — stop and fix, or surface the failure to me.

Execute in this order, stopping on first failure:

1. **Lint:**
   ```bash
   swiftlint --strict
   ```

2. **Build the main app:**
   ```bash
   xcodebuild -scheme WhisprLocalApp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -60
   ```

3. **Build the keyboard extension:**
   ```bash
   xcodebuild -scheme WhisprKeyboard -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -60
   ```

4. **Run unit tests:**
   ```bash
   xcodebuild test -scheme WhisprLocalApp \
     -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' 2>&1 | tail -80
   ```

5. **Run Shared package tests:**
   ```bash
   swift test --package-path Shared 2>&1 | tail -40
   ```

Then report in this format:

```
/verify results
- Lint:            PASS / FAIL (N violations)
- App build:       PASS / FAIL
- Keyboard build:  PASS / FAIL
- App tests:       PASS / FAIL (X passed, Y failed, Z skipped)
- Shared tests:    PASS / FAIL (X passed, Y failed, Z skipped)

Summary: <one sentence>
Blocking issues: <none | list>
```

If anything is FAIL, show the relevant error output and propose a fix before making any further changes.

> Build invocations here must stay in sync with `CLAUDE.md` §"Regular workflow". If you change one, change both.
