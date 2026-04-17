# Contributing to WhisprLocal

Thanks for your interest. WhisprLocal is built in the open and welcomes
contributions — particularly those that sharpen the core promise:
**fully on-device voice-to-text, zero cloud dependencies.**

Read `CLAUDE.md` and `PROJECT_SPEC.md` before opening a non-trivial PR.
They encode the constraints that make this project different from every
other dictation app.

## First-time setup

```bash
# Requires macOS 14+ and full Xcode 16+ at /Applications/Xcode.app
brew install xcodegen swiftlint mint
mint bootstrap                          # pins tool versions from Mintfile
xcodegen generate                       # creates WhisprLocal.xcodeproj
open WhisprLocal.xcodeproj
```

Run `swift test --package-path Shared` and `xcodebuild test
-scheme WhisprLocalApp -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro'`
to confirm the environment is healthy before you start changing things.

## Workflow

1. **Pick a milestone.** Work happens on `milestone/M<n>-<slug>` branches
   off `main`. Do not collapse or skip milestones — the ordering is
   load-bearing (see `PROJECT_SPEC.md` §11).
2. **Plan before code.** For any non-trivial change, post a numbered plan
   in your PR description or issue comment before writing files. Review
   happens on the plan first, implementation second.
3. **Small commits.** Conventional Commits (`feat:`, `fix:`, `chore:`,
   `docs:`, `test:`, `refactor:`, `ci:`). Every commit must compile.
4. **Run the gate quartet before opening a PR:**

   ```
   /spec-check       # catches drift from PROJECT_SPEC.md
   /verify           # lint + build both targets + run tests
   /audit-privacy    # greps for forbidden patterns (network, SDKs, ML in keyboard)
   /memory-check     # estimates WhisprKeyboard memory footprint
   ```

   All four must be green. Paste the output in the PR description.

## Code style

Covered in detail in `CLAUDE.md` § "Code style". Highlights:

- Swift 5.10+. SwiftUI for main-app UI. UIKit only inside the keyboard
  extension (`KeyboardViewController` is UIKit by platform requirement).
- One type per file. Filename matches type name.
- `// MARK: - Section` dividers in any file over ~100 lines.
- Dependency injection via initializers. No singletons except
  `FileManager.default`, `UserDefaults.standard`, `Bundle.main`.
- Async/await everywhere. Combine only if a specific API forces it.
- SwiftLint is enforced in CI with `--strict`.

## What will not be accepted

- **Cloud AI dependencies.** No OpenAI, Anthropic, Google, Azure.
  Not even "optional for better quality."
- **Analytics/telemetry/crash SDKs.** Mixpanel, Firebase, Sentry,
  Amplitude, PostHog, Bugsnag — all banned. Diagnostics via `OSLog`
  only.
- **ML imports inside `WhisprKeyboard/`.** The 48 MB iOS memory ceiling
  makes this architecturally impossible, not a preference.
- **Hardcoded model choices.** Models always go through `ModelCatalog`.
  The catalog is the contract with the user.
- **Persisted audio.** WAV files in `inbox/` delete after
  transcription; polished text in `outbox/` deletes within 60 s.

## PR hygiene

- Title follows Conventional Commits.
- Description includes: summary, screenshots / GIF if UI-touching, test
  plan, `/audit-privacy` output, links to the spec section(s) this PR
  addresses.
- A note calling out any `CLAUDE.md` or `PROJECT_SPEC.md` change,
  because those are the contracts and drift there is expensive.

## Reporting bugs and privacy issues

Open a GitHub issue with reproduction steps. For anything that looks
like a privacy violation (network call to an unexpected domain, data
persisting across sessions, a log line you didn't expect), please
email privately first — we treat those as security-severity.

## License

MIT. By contributing, you agree your contributions will be licensed
under the same terms as the rest of the project.
