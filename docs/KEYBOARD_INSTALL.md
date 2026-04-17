# Installing the WhisprKeyboard

How to enable the WhisprLocal system keyboard on your iPhone.

> **Status: stub.** This document is populated at **M4** (Keyboard
> extension, App Group hand-off, Darwin notifications). At M0 the
> keyboard is a placeholder that renders a "WhisprLocal" label — nothing
> to enable yet. The full install flow, including the Full Access
> explanation card, ships with M4.

## What will live here

- Step-by-step Settings → General → Keyboard → Keyboards → Add New Keyboard
  walkthrough, with screenshots.
- **Why "Allow Full Access" is required** — we use it for App Group file
  access and URL-scheme hand-off to the main app, not for any network
  transmission. Everything stays on your device.
- Troubleshooting: keyboard not appearing, Full Access toggle not
  sticking, transcription appearing to hang.
- How to remove the keyboard if you no longer want it.

## Privacy pre-flight

Before M4 lands, a quick reminder of what the keyboard is (and is not)
allowed to do — see `docs/PRIVACY.md`:

- **Does** capture microphone audio while you explicitly tap-and-hold (or
  toggle) the mic button.
- **Does** write that audio to the App Group shared container for the main
  app to process.
- **Does not** have network access at runtime. Ever.
- **Does not** load Whisper, MLX, or any ML framework inside the
  extension. The 48 MB iOS memory ceiling makes that impossible by design.
