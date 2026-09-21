# Codex Usage Repository Guide

## Product invariants

- Build a native macOS 13+ menu-bar app with no Dock icon or main window.
- Display only the primary `codex` allowance. Keep auxiliary buckets such as `base_model_inference` and `gpt-reserve` out of the UI.
- Show a reset count only when `availableCount > 0`. Every reset redemption requires visible confirmation and one idempotency key reused for an uncertain retry.
- Automated verification is read-only against the live account; it never consumes a reset.
- Appearance choices are Light and Dark. Apply appearance to the popover window only, leaving the menu-bar title under macOS contrast control.
- Language choices are English and Simplified Chinese. Fresh installs and migrated legacy `system` values default to English.
- Use `docs/images/codex-usage-compact-no-system.png` as the visual target and keep `design-qa.md` current after visual changes.

## Workflow

1. Inspect the relevant source and tests before editing.
2. For behavior changes and bug fixes, write a focused failing test and observe RED before production code.
3. Run focused tests with `scripts/test.sh --filter <name>`.
4. Run the complete suite with `scripts/test.sh`.
5. For Codex protocol work, also run the read-only integration test:

   ```bash
   CODEX_USAGE_RUN_INTEGRATION=1 scripts/test.sh --filter AppServerIntegrationTests
   ```

6. Build and verify the app:

   ```bash
   swift build -c release --product CodexUsage -Xswiftc -warnings-as-errors
   Tests/PackagingTests.sh
   codesign --verify --deep --strict dist/CodexUsage.app
   scripts/smoke-test.sh
   ```

The installed Command Line Tools SwiftPM runner does not execute registered tests correctly. Use `scripts/test.sh`, which links the same test objects to Apple's Testing entry point.

## Versioning

`Packaging/Info.plist` is the version source of truth. Every code change increments `CFBundleShortVersionString` once using `a.b.c` semantic versioning and increments the integer `CFBundleVersion` once.

- **Major (`a`)**: incompatible behavior, removed compatibility, or a breaking interface. Increment `a`; reset `b` and `c` to zero.
- **Minor (`b`)**: backward-compatible user-visible functionality. Increment `b`; reset `c` to zero.
- **Patch (`c`)**: backward-compatible bug fix, reliability fix, performance fix, or internal correction. Increment `c`.

Examples:

- `0.2.0` → `0.2.1` for a bug fix.
- `0.2.1` → `0.3.0` for a new feature.
- `0.3.4` → `1.0.0` for a breaking release.

Documentation-only edits do not require a version bump unless they describe a shipped behavior change that also changes code. Keep the visible version label derived from the bundle; never hardcode it in SwiftUI.

## Architecture pointers

- `Sources/CodexUsageCore`: protocol models, formatting, preferences, controller state, localization, version parsing, and App Server transport.
- `Sources/CodexUsageApp`: `MenuBarExtra` entry point and SwiftUI popover.
- `Packaging/Info.plist`: bundle metadata and version source.
- `Tests/CodexUsageCoreTests`: behavior and protocol tests.
- `Tests/PackagingTests.sh`: bundle layout, metadata, and signature contract.

Keep credentials inside Codex App Server. Application code must not read, log, or persist ChatGPT tokens, account identifiers, or reset-credit identifiers.
