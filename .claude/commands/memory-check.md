---
description: Estimate the keyboard extension's memory footprint and flag risk of blowing the 48MB ceiling
---

Audit `WhisprKeyboard/` for anything that risks the **48 MB memory ceiling** iOS imposes on custom keyboard extensions.

### 1. Confirm no ML imports

```bash
rg -n --type swift '^\s*import\s+(WhisperKit|MLX|MLXLLM|MLXNN|MLXRandom|MLXLMCommon|CoreML)' WhisprKeyboard/ \
  && echo "✗ FATAL: ML import in keyboard extension" \
  || echo "✓ No ML imports"
```

A single WhisperKit or MLX import loads binary frameworks that blow the budget even before inference.

### 2. List all imports in the keyboard target

```bash
rg -n --type swift '^\s*import\s+\S+' WhisprKeyboard/ | sort -u
```

The expected set is roughly:
- `UIKit`
- `AVFoundation`
- `AudioToolbox`
- `SwiftUI` (optional, only if using SwiftUI-in-UIKit wrappers)
- `WhisprShared` (our own package)
- `OSLog`

Flag anything else for review.

### 3. Check for heavy frameworks

```bash
rg -n --type swift '^\s*import\s+(CoreML|Vision|NaturalLanguage|Speech|AVFAudio)' WhisprKeyboard/
```

`CoreML` / `Vision` / `NaturalLanguage` are fine individually but all three together push the baseline memory above 20 MB. Flag if multiple are present.

### 4. Look for large resource loads

```bash
rg -n --type swift 'Bundle.*\.url\(forResource|UIImage\(named:|NSDataAsset' WhisprKeyboard/
```

Any asset load should be lazy. Flag any that happen in `viewDidLoad`, `init`, or `loadView`.

### 5. Check audio buffer sizing

```bash
rg -n --type swift 'AVAudioPCMBuffer|frameCapacity|installTap' WhisprKeyboard/
```

The AVAudioEngine tap should use a small buffer (e.g., 4096 frames). Large `frameCapacity` values hold memory unnecessarily. Flag anything over 8192.

### 6. Check for Combine subscriptions that retain state

```bash
rg -n --type swift 'sink\s*\{|assign\(to:' WhisprKeyboard/
```

Keyboards should minimize Combine usage. Each chain retains closures. Prefer plain delegation or async streams.

### 7. Build and check binary size

```bash
xcodebuild -scheme WhisprKeyboard -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Then, after a build, check the `.appex` size:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "WhisprKeyboard.appex" -type d | head -1 | xargs du -sh
```

The binary itself should stay under ~5 MB. Much larger means transitive linkage of something heavy.

### 8. Suggest profiling step

Remind me to test on a real device with Instruments' Allocations instrument attached to the keyboard extension process. Simulator does not enforce the 48 MB limit; real devices do, and they kill the process silently.

### Report format

```
/memory-check results
- ML imports in keyboard:  CLEAN / VIOLATED
- Import surface:          <count> imports, <list anything unexpected>
- Heavy frameworks:        CLEAN / <list>
- Eager asset loads:       <count>, <list locations>
- Audio buffer sizing:     OK / CONCERN (details)
- Combine retention risk:  <count> subscriptions
- .appex binary size:      X.X MB
- Build status:            PASS / FAIL

Verdict: LOW RISK / MEDIUM RISK / HIGH RISK

Next action: <e.g., "profile with Instruments" / "remove the NaturalLanguage import" / "lazy-load the waveform asset">
```
