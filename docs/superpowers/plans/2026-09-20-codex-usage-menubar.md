# Codex Usage Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that displays remaining Codex usage, conditionally displays and safely consumes banked resets, remembers the latest reset result, and switches appearance and language at runtime.

**Architecture:** A Swift Package contains a testable `CodexUsageCore` library and a SwiftUI `MenuBarExtra(.window)` executable. The core owns formatting, preferences, controller state, Codex binary discovery, and a JSONL client for `codex app-server`; the app target renders the selected horizontal-bar interface.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, Foundation, Swift Testing, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-20-codex-usage-menubar-design.md`

## Global Constraints

- Minimum deployment target: macOS 13.
- No third-party dependencies and no full-Xcode requirement.
- Use existing Codex authentication; never read or persist tokens.
- Never consume a real reset during automated verification.
- Default appearance and language are both `system`.
- System language resolves every `zh-*` locale to Simplified Chinese and all other locales to English.
- Keep `.smart/` untracked and untouched.

## Review Focus

- Missing or malformed reset data must hide the status suffix and keep the UI usable.
- An uncertain consume request must retry with the same idempotency key, never a new one.
- Unexpected app-server output and process termination must not freeze the UI or strand pending work.
- Manual language and appearance selections must override system changes and survive relaunch.
- Packaging must include `LSUIElement=true`, the release executable, and a valid ad-hoc signature.

---

### Task 1: Package Foundation and Usage Domain

**Files:** `Package.swift`, `.gitignore`, `Sources/CodexUsageCore/UsageModels.swift`, `Sources/CodexUsageCore/UsageFormatting.swift`, `Tests/CodexUsageCoreTests/UsageDomainTests.swift`, design spec.

**Interfaces:** Produces `UsageSnapshot`, `RateLimitBucket`, `ResetCredit`, `ResetOutcome`, `AppLanguage`, and `UsageFormatting` for later tasks.

- [ ] Write failing tests for bucket fallback, clamping and rounding, reset suffix rules, English and Chinese titles, partial JSON, and all reset outcomes.
- [ ] Run `swift test --filter UsageDomainTests` and confirm failure because the domain API is absent.
- [ ] Implement the minimal domain and formatter behavior, including forward-compatible reset outcome decoding.
- [ ] Update the spec with language behavior and the final status-title rules.
- [ ] Run `swift test --filter UsageDomainTests`, then `swift test`, and commit.

### Task 2: Preferences, Localization, and Controller State

**Files:** core preference/localization/controller sources and their tests.

**Interfaces:** Produces `PreferencesStore`, `LocalizationCatalog`, `UsageService`, and `@MainActor UsageController`.

- [ ] Write failing tests for language resolution, copy-key parity, localized dates/results, invalid stored values, persistence, serialized refresh, and idempotency-key reuse.
- [ ] Verify the focused tests fail for missing APIs.
- [ ] Implement typed localized copy, preferences, and controller state transitions.
- [ ] Run focused tests and the full suite, then commit.

### Task 3: Codex App Server Client

**Files:** binary locator, JSONL transport, app-server client, protocol fixtures, unit tests, and opt-in integration test.

**Interfaces:** Implements `UsageService` with `CodexAppServerClient`.

- [ ] Write failing tests for binary precedence, initialize ordering, notification skipping, response matching, JSON-RPC errors, timeout, termination recovery, and reset payloads.
- [ ] Verify focused tests fail for missing client behavior.
- [ ] Implement the process transport and client with a 10-second timeout and restart-on-next-request behavior.
- [ ] Add an integration test gated by `CODEX_USAGE_RUN_INTEGRATION=1` that calls only `account/rateLimits/read`.
- [ ] Run focused tests and the full suite, then commit.

### Task 4: Localized Menu Bar Interface

**Files:** `Sources/CodexUsageApp/CodexUsageApp.swift`, view components, and UI-state tests.

**Interfaces:** Consumes `UsageController`, `LocalizationCatalog`, `AppLanguage`, and `AppAppearance`.

- [ ] Write failing tests for UI presentation state, localized menu labels, reset enablement, and appearance/language checkmarks.
- [ ] Implement the selected horizontal usage-bar popover using `MenuBarExtra(.window)`.
- [ ] Add reset confirmation, manual refresh, additional buckets, recent result, language, appearance, and quit controls.
- [ ] Run focused tests, `swift test`, and `swift build`, then commit.

### Task 5: Packaging and End-to-End Verification

**Files:** `Packaging/Info.plist`, `scripts/build-app.sh`, `scripts/smoke-test.sh`, and README usage notes.

**Interfaces:** Produces `dist/CodexUsage.app` with bundle identifier `local.codexusage.menubar`.

- [ ] Add packaging behavior checks for bundle layout and `LSUIElement=true`.
- [ ] Implement release build, deterministic bundle staging, and ad-hoc signing.
- [ ] Run `swift test`, the opt-in real read-only integration test, `swift build -c release`, packaging, `codesign --verify --deep --strict`, and the exact-PID smoke test.
- [ ] Launch the packaged app and inspect the status item, popover, languages, and appearances without consuming a reset.
- [ ] Commit packaging and verification artifacts, excluding `dist/`.

### Final Review

- [ ] Review the complete diff against the spec and this plan; because the user explicitly selected native execution without subagents, perform and record a separate self-review.
- [ ] Fix Critical or Important findings with a failing regression test followed by a green full suite.
- [ ] Run all final verification commands fresh and report evidence, rulings, and any deferred minor findings.
