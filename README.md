<div align="center">

# Codex Usage

**Codex usage windows and available reset count, right in your macOS menu bar.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](#build-and-run)
[![Status: Local build verified](https://img.shields.io/badge/status-local%20build%20verified-22C55E)](#build-and-run)
[![License: MIT](https://img.shields.io/badge/license-MIT-22C55E)](LICENSE)

[Chinese](README.zh-CN.md)

[**Download the latest release**](https://github.com/hinson0/codex-usage/releases/latest)

<img src="docs/images/codex-usage-dual-window.png" alt="Compact Codex Usage menu bar popover with weekly allowance and unlimited five-hour status" width="100%">

<sub>Selected compact design target in light and dark appearances.</sub>

</div>

---

### About

Codex Usage is a lightweight, native macOS menu bar utility for checking your remaining Codex allowance without opening a dashboard. It reads the official five-hour and longer-window data when available, and shows banked reset count as read-only information.

The status title stays deliberately compact:

```text
Codex 99%                    Longer window only; five-hour use is unlimited
Codex 82%-94%                Five-hour remaining, then longer-window remaining
Codex 82%-94% (2 resets)     Two banked resets available
```

### Target experience

- Five-hour and longer-window remaining percentages when both limits exist.
- A clear “Unlimited” five-hour row when the official response has no five-hour window.
- Longer-window allowance with a compact horizontal progress bar and reset time.
- Read-only reset count shown only when one or more resets are available.
- Automatic refresh on launch, every 60 seconds, and when the popover opens.
- Light and Dark appearances.
- English and Simplified Chinese languages, defaulting to English.
- Localized “Check for Updates…” action with scheduled Sparkle update checks.
- No Dock icon and no full application window.

### Downloads and updates

Each GitHub Release provides two application packages:

- `CodexUsage-vX.Y.Z-macOS.dmg` is the friendly manual installer. Open it and
  drag Codex Usage into Applications.
- `CodexUsage-vX.Y.Z-macOS.zip` is the exact signed archive used by Sparkle for
  in-app updates.

The Release also includes `SHA256SUMS` and the signed `appcast.xml` update feed.
Version `0.4.3` is the first Sparkle-enabled build, so it must be installed
manually; later releases can be found from “Check for Updates…” and by scheduled
background checks. Updates are never installed silently.

### Privacy and safety

- Uses the official local Codex App Server and your existing Codex sign-in.
- Does not read, copy, or persist ChatGPT access tokens.
- Does not consume resets or save reset-attempt history.
- Communicates with a local child process over pipes; it does not open a listening network port.
- Automated verification is read-only and never consumes a real reset.

### Build and run

The app builds with Apple Command Line Tools; full Xcode is not required. From the repository root:

```bash
scripts/test.sh
scripts/build-app.sh
open dist/CodexUsage.app
```

`scripts/build-app.sh` creates an ad-hoc-signed local build at `dist/CodexUsage.app`.
The public DMG is currently ad-hoc signed too, so Gatekeeper may warn on the
first launch. A DMG improves installation ergonomics; only Developer ID signing
and notarization can remove that warning properly.

### Requirements

- macOS 13 or later.
- Apple Silicon or Intel Mac supported by the final Swift build.
- Codex CLI or the ChatGPT/Codex desktop app installed.
- A ChatGPT account already signed in to Codex.

### License

Released under the [MIT License](LICENSE). You are free to use, modify, redistribute, and use it commercially, provided the copyright and permission notice remain with copies of the software.

### Documentation

- [Design QA](design-qa.md)
