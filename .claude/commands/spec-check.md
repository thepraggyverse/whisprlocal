---
description: Re-read PROJECT_SPEC.md and flag any drift between the current codebase and the spec
---

Re-read `PROJECT_SPEC.md` in full, then audit the current branch for drift from the spec.

### 1. Tech stack check

Confirm the codebase uses only the tools in spec §3:
- Swift 5.10+ / Swift 6
- SwiftUI + minimal UIKit (keyboard only)
- iOS 17.0 minimum deployment target
- SPM dependencies: **only** WhisperKit and MLX Swift Examples (plus LocalLLMClient if explicitly enabled behind a feature flag)
- No CocoaPods, no Carthage

```bash
# Check deployment target
rg -n 'IPHONEOS_DEPLOYMENT_TARGET|deploymentTarget' project.yml Package.swift

# List every SPM dependency
rg -n 'url:|package:' project.yml Shared/Package.swift 2>/dev/null

# Check for forbidden package managers
ls Podfile Cartfile 2>/dev/null && echo "✗ Forbidden package manager detected"
```

### 2. File structure check

Compare current structure to spec §9:
```bash
# Portable (no `tree` dependency — it's not in our Mintfile). Use `find`:
find . -maxdepth 3 -type d \
  \( -name DerivedData -o -name .build -o -name .git -o -name node_modules \) -prune \
  -o -type d -print \
  | sort
```

Flag any top-level directory that isn't in the spec, and any missing one.

### 3. Feature scope check

For each M-prefixed milestone that's been merged, confirm the feature exists:
- **M1:** Audio capture with waveform → `rg -l 'AVAudioEngine' WhisprLocalApp/`
- **M2:** Model catalog + WhisperKit → `rg -l 'ModelCatalog|WhisperKit' WhisprLocalApp/`
- **M3:** Polish engine + prompt templates → `rg -l 'PolishEngine|polish_default' WhisprLocalApp/`
- **M4:** Keyboard extension handoff → `rg -l 'JobEnvelope|DarwinNotification' WhisprKeyboard/`
- **M5:** Command Mode, Dictionary, Snippets → `rg -l 'CommandMode|Dictionary|Snippet' WhisprLocalApp/`
- **M6:** History (SwiftData) → `rg -l '@Model|SwiftData' WhisprLocalApp/`
- **M7:** Privacy Audit screen → `rg -l 'PrivacyAudit' WhisprLocalApp/`

For each milestone in `CLAUDE.md` marked complete but missing evidence in code: FLAG.

### 4. Anti-pattern sweep

Re-run key forbidden-pattern checks:
```bash
# No cloud AI SDKs
rg -in 'import\s+(OpenAI|Anthropic|GoogleGenerativeAI|OpenAIKit)' .

# No ML in keyboard
rg -in 'import\s+(WhisperKit|MLX)' WhisprKeyboard/

# No analytics
rg -in 'Mixpanel|Segment\.|Firebase|Sentry|Amplitude|PostHog|Bugsnag|Crashlytics'
```

All should return empty.

### 5. Model catalog integrity

Confirm `docs/MODEL_CATALOG.md` matches the JSON shipped in the app and matches spec §4:
```bash
cat WhisprLocalApp/Resources/ModelCatalog.json 2>/dev/null | jq -r '.models[].id' | sort
```
Should include at minimum: `whisper-tiny-en`, `whisper-base`, `whisper-small`, `qwen2.5-1.5b-instruct-4bit`, `gemma-2-2b-it-4bit`.

### 6. Privacy posture

Quick sanity check that spec §8 commitments are intact:
- ATS configured to deny-by-default? `rg -n 'NSExceptionDomains' project.yml`
- Privacy Audit screen present? `rg -l 'PrivacyAuditView' WhisprLocalApp/`
- `docs/PRIVACY.md` exists and matches §8? `[ -f docs/PRIVACY.md ] && echo exists`

### Report format

```
/spec-check results

Tech stack:           ALIGNED / DRIFT — <details>
File structure:       ALIGNED / DRIFT — <details>
Completed milestones: <list>
Missing milestone evidence: <list>
Anti-patterns found:  <none | list>
Model catalog:        ALIGNED / DRIFT
Privacy posture:      ALIGNED / DRIFT — <details>

Overall: ALIGNED / NEEDS ATTENTION

Drift items requiring decision:
1. ...
2. ...
```

If drift is found, propose whether to (a) update the code to match the spec, or (b) update the spec with justification for the deviation. Do not silently accept drift.
