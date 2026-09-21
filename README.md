<div align="center">

# Codex Usage

**Codex usage and banked resets, right in your macOS menu bar.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](#build-and-run)
[![Status: Local build verified](https://img.shields.io/badge/status-local%20build%20verified-22C55E)](#build-and-run)
[![License: MIT](https://img.shields.io/badge/license-MIT-22C55E)](LICENSE)

[Chinese](README.zh-CN.md)

<img src="docs/images/codex-usage-compact-no-system.png" alt="Compact Codex Usage menu bar popover in light and dark appearances" width="100%">

<sub>Selected compact design target in light and dark appearances.</sub>

</div>

---

### About

Codex Usage is a lightweight, native macOS menu bar utility for checking your remaining Codex allowance without opening a dashboard. When your account has banked resets, the available count appears beside the percentage and you can redeem one from the popover after a confirmation.

The status title stays deliberately compact:

```text
Codex 100%             No reset available
Codex 73% (2 resets)  Two resets available
```

### Target experience

- Primary Codex allowance with a compact horizontal progress bar.
- Reset count shown only when one or more resets are available.
- Clear “no reset available” state when the count is zero.
- Confirm-before-redeem reset action with idempotent retry protection.
- The three most recent reset attempts stored locally, newest first.
- Automatic refresh on launch, every 60 seconds, and when the popover opens.
- Light and Dark appearances.
- English and Simplified Chinese languages, defaulting to English.
- No Dock icon and no full application window.

### Privacy and safety

- Uses the official local Codex App Server and your existing Codex sign-in.
- Does not read, copy, or persist ChatGPT access tokens.
- Reset history contains only attempts made through this app; the App Server does not expose ChatGPT's web history.
- Communicates with a local child process over pipes; it does not open a listening network port.
- Never redeems a reset automatically.
- Automated tests never consume a real reset.

### Build and run

The app builds with Apple Command Line Tools; full Xcode is not required. From the repository root:

```bash
scripts/test.sh
scripts/build-app.sh
open dist/CodexUsage.app
```

`scripts/build-app.sh` creates an ad-hoc-signed local build at `dist/CodexUsage.app`. It is intended for this Mac; distributing it to other Macs requires Developer ID signing and notarization.

### Requirements

- macOS 13 or later.
- Apple Silicon or Intel Mac supported by the final Swift build.
- Codex CLI or the ChatGPT/Codex desktop app installed.
- A ChatGPT account already signed in to Codex.

### License

Released under the [MIT License](LICENSE). You are free to use, modify, redistribute, and use it commercially, provided the copyright and permission notice remain with copies of the software.

### Documentation

- [Product design and technical specification](docs/superpowers/specs/2026-09-20-codex-usage-menubar-design.md)
