---
description: Grep the codebase for forbidden network, telemetry, and privacy-violating patterns
---

Audit the codebase against WhisprLocal's privacy contract. Report any violations — do not fix silently; surface them.

Run these checks from the repo root:

### 1. Forbidden SDKs
Search for any import of a banned analytics/telemetry/crash SDK:
```bash
rg -i --type swift '^\s*import\s+(Mixpanel|Segment|Firebase|Sentry|Amplitude|PostHog|Bugsnag|Crashlytics|Datadog|Adjust|AppsFlyer|Branch)' . || echo "✓ No forbidden SDK imports"
```

### 2. Disallowed network hosts
Search for any URL string or host that isn't on the allowlist. The only allowed hosts at runtime are `huggingface.co` and `cdn-lfs.huggingface.co` (for user-initiated model downloads).
```bash
rg -n --type swift 'https?://' . \
  | rg -v 'huggingface\.co|cdn-lfs\.huggingface\.co' \
  | rg -v '// ' \
  | rg -v 'test|Test|mock|Mock|fixture|Fixture|example\.com|localhost' \
  || echo "✓ No non-allowlisted URLs in source"
```

### 3. URLSession outside allowlisted context
Any `URLSession` or `URLRequest` use that isn't in `ModelDownloader.swift` is suspicious. List them:
```bash
rg -n --type swift 'URLSession|URLRequest|URL\(string:' . \
  | rg -v 'ModelDownloader\.swift|Tests/'
```
Expected output: nothing, or only commented-out code.

### 4. ATS (App Transport Security) configuration
Check `Info.plist` (or equivalent in `project.yml`) to confirm `NSAllowsArbitraryLoads` is absent or `false`, and `NSExceptionDomains` only contains `huggingface.co`:
```bash
rg -n 'NSAllowsArbitraryLoads|NSExceptionDomains|NSAppTransportSecurity' \
  project.yml \
  WhisprLocalApp/Info.plist \
  WhisprKeyboard/Info.plist \
  2>/dev/null
```

### 5. Keyboard extension imports
`WhisprKeyboard/` must never import `WhisperKit` or `MLX*`. Check:
```bash
rg -n --type swift '^\s*import\s+(WhisperKit|MLX|MLXLLM|MLXNN|MLXRandom|MLXLMCommon)' WhisprKeyboard/ \
  && echo "✗ FORBIDDEN: ML import in keyboard extension" \
  || echo "✓ No ML imports in keyboard"
```

### 6. Audio persistence
Check that audio files in `inbox/` get deleted after transcription. Search for a deletion call in the transcription flow:
```bash
rg -n --type swift 'FileManager.*removeItem|try.*remove.*inbox' .
```
Expected: at least one match in the transcription pipeline.

### 7. File protection attributes
Every write to the App Group container must set `NSFileProtectionComplete`:
```bash
rg -n --type swift '\.write\(to:|FileManager.*createFile' . \
  | rg -v 'Tests/' \
  | while read line; do
      echo "REVIEW: $line (confirm NSFileProtectionComplete is set nearby)"
    done
```

### 8. Clipboard / pasteboard writes
Only the main app's "Copy to clipboard" feature should call `UIPasteboard`. Keyboard extension should never write to pasteboard:
```bash
rg -n --type swift 'UIPasteboard' WhisprKeyboard/ \
  && echo "✗ Keyboard must not use pasteboard" \
  || echo "✓ Keyboard clean"
```

### Report format

```
/audit-privacy results
- Forbidden SDKs:          CLEAN / N violations
- Disallowed hosts:        CLEAN / N violations
- URLSession usage:        CLEAN / N suspicious sites
- ATS config:              OK / MISCONFIGURED
- Keyboard ML imports:     CLEAN / VIOLATED
- Audio deletion:          PRESENT / MISSING
- File protection:         N writes reviewed
- Pasteboard in keyboard:  CLEAN / VIOLATED

Overall verdict: PASS / FAIL
```

If any check fails, stop and surface it to me with the exact line numbers and a proposed fix.
