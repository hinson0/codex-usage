# Codex Usage Menu Bar App Design

## Goal

Build a lightweight native macOS menu bar app that shows the remaining main Codex allowance and the number of available banked resets at a glance.

The status item conditionally includes the reset count:

```text
Codex 100%
Codex 73%(2 次)
```

When no reset is available, the count and parentheses are omitted entirely. When one or more resets are available, the title appends `(<count> 次)`.

The app must also let the user consume an available reset, clearly report when no reset exists, and retain the time and outcome of the most recent reset attempt.

## Confirmed Environment

- macOS 26.6.2 on Apple Silicon (`arm64`).
- Apple Swift 6.3.3 is available through Command Line Tools.
- Full Xcode is not installed, so the project must build without `xcodebuild`.
- Codex CLI 0.154.0 is installed at `~/.local/bin/codex`.
- ChatGPT/Codex desktop app 26.915.31945 is installed in `/Applications/ChatGPT.app` and contains a bundled Codex binary.
- The Codex App Server responds successfully to `account/rateLimits/read` with the existing ChatGPT login.

## Scope

### Included

- A menu-bar-only native app with no Dock icon.
- Remaining percentage for the primary `codex` rate-limit bucket.
- Available reset count in the status bar title.
- A detailed menu with quota timing, reset availability, refresh state, last reset record, manual refresh, and quit.
- Confirmed consumption of one reset through Codex App Server.
- A native appearance submenu with Follow System, Light, and Dark choices.
- A language submenu with Follow System, English, and Simplified Chinese choices.
- Automatic refresh and recovery when the App Server process exits.
- Local persistence for the most recent reset attempt, selected appearance, and selected language.
- A polished bilingual README and public-repository-safe design assets.
- Unit tests, an App Server read-only integration probe, release compilation, `.app` packaging, ad-hoc signing, and a launch smoke test.

### Not Included

- Purchasing credits or resets.
- Automatic reset consumption.
- Login-item installation.
- A Dock window, charts, notifications, or historical usage analytics.
- Storage or direct handling of ChatGPT access tokens.
- Publishing, notarization, or a Developer ID signature.

## Architecture

The app is a Swift Package containing one executable and one test target. The executable uses AppKit directly so it can be compiled by `swift build` with the installed Command Line Tools.

The major components are:

1. **CodexAppServerClient**
   - Locates a usable Codex binary.
   - Starts `codex app-server` as a child process over stdin/stdout.
   - Performs the required `initialize` and `initialized` handshake.
   - Sends newline-delimited JSON requests and matches responses by request ID.
   - Exposes typed operations for reading rate limits and consuming one reset.
   - Restarts the child process after unexpected termination.

2. **UsageModels and UsageFormatter**
   - Decode only the protocol fields needed by this app while tolerating unknown fields.
   - Select the `codex` bucket from `rateLimitsByLimitId`, falling back to the legacy `rateLimits` field.
   - Calculate remaining percentage as `clamp(100 - usedPercent, 0...100)` and round it to a whole number for the status title.
   - Treat `rateLimitResetCredits.availableCount` as authoritative.

3. **UsageController**
   - Owns the current loading, loaded, and error states.
   - Refreshes on launch, every 60 seconds, after opening the menu, and after any reset response.
   - Serializes refresh and reset operations so UI actions cannot create overlapping requests.
   - Publishes main-thread state for the AppKit menu.

4. **PreferencesStore**
   - Stores one reset record in `UserDefaults`: attempted timestamp, outcome, and optional user-facing error text.
   - Stores the selected appearance as `system`, `light`, or `dark`; the default is `system`.
   - Stores the selected language as `system`, `english`, or `zhHans`; the default is `system`.
   - Never stores credentials, account identifiers, or reset credit identifiers.

5. **MenuBarApplication**
   - Creates a SwiftUI `MenuBarExtra` using window-style content.
   - Updates the status title and popover from controller state.
   - Presents a SwiftUI confirmation alert before consuming a reset.
   - Applies the selected appearance to the status-menu UI without changing the system-wide macOS setting.
   - Resolves the selected language at runtime and updates every visible string without relaunching.
   - Uses `LSUIElement=true` in the packaged app so it has no Dock icon.

## Codex Binary Discovery

The app searches these candidates in order and verifies that each is executable:

1. `CODEX_BIN`, when explicitly provided in the process environment.
2. `~/.local/bin/codex`.
3. `/Applications/ChatGPT.app/Contents/Resources/codex`.
4. `/opt/homebrew/bin/codex`.
5. `/usr/local/bin/codex`.
6. `codex` resolved from the inherited `PATH`.

Failure to locate a binary is shown as an actionable menu error rather than terminating the app.

## Data Flow

### Refresh

1. Start and initialize the App Server if it is not already ready.
2. Call `account/rateLimits/read`.
3. Prefer `rateLimitsByLimitId["codex"]`; otherwise use `rateLimits`.
4. Derive the remaining percentage from `usedPercent`.
5. Read the reset count from `rateLimitResetCredits.availableCount`; missing reset data is treated as zero available resets for UI purposes.
6. Refresh the menu bar title and menu details on the main thread.

### Reset Consumption

1. Render **“当前没有可用 reset”** as a disabled menu item when the authoritative available count is zero.
2. When the count is positive, show **“使用 1 次 reset…”**.
3. Clicking the item opens a confirmation alert that explains one banked reset will be consumed.
4. On confirmation, generate one UUID idempotency key and select the first available opaque credit ID when details are present. If only the count is known, omit the credit ID and let the service choose.
5. Call `account/rateLimitResetCredit/consume`.
6. Treat `reset` and `alreadyRedeemed` as success. Record all defined outcomes (`reset`, `alreadyRedeemed`, `nothingToReset`, and `noCredit`) verbatim with localized display text.
7. For an uncertain transport failure, retry at most once with the same idempotency key. Never generate a new key for that logical attempt.
8. Persist the final time and outcome, then call `account/rateLimits/read` instead of inferring new usage values.

## User Interface

### Status Bar

- Loaded with no resets: `Codex <remaining>%`.
- Loaded with resets in Simplified Chinese: `Codex <remaining>%(x 次)`.
- Loaded with resets in English: `Codex <remaining>% (x resets)` with singular `reset` for one.
- Loading with no cached snapshot: `Codex --%`.
- Error with a cached snapshot: keep the last values and expose the error in the menu.
- Error without a cached snapshot: `Codex --%`.

### Selected Visual Direction

The selected design is the integrated-preferences-footer direction shown in the project reference image at `docs/images/codex-usage-integrated-footer.png`.

- The popover is 432 points wide and uses a thin horizontal bar for the primary Codex remaining percentage.
- Information uses a 20-point outer inset, stronger typography hierarchy, and lightweight separators.
- Blue is reserved for the usage bar and enabled reset action.
- Light and dark appearances keep the same hierarchy, spacing, and controls.
- The native material, text, separators, and status-bar treatment adapt to the selected appearance.
- Auxiliary quota buckets such as `base_model_inference` / `gpt-reserve` never appear in the popover.
- Appearance and language form one subtle two-cell preferences footer below reset status rather than interrupting the usage flow.

### Menu

The menu is ordered as follows:

1. Primary Codex allowance, remaining percentage, and next automatic reset time.
2. Current error, only when present.
3. Reset action or disabled **“当前没有可用 reset”**.
4. Last reset time and result, or **“尚未使用过 reset”**.
5. A unified two-cell preferences footer: **“外观 · 当前值”** and **“语言 · 当前值”**, each opening its native menu with the active option checked.
6. **“立即刷新”**.
7. **“退出”**.

Dates use the effective app language and current system time zone.

### Localization

- System language maps any `zh-*` locale to Simplified Chinese; other locales use English.
- A manual language choice overrides later system-language changes and survives relaunch.
- English and Simplified Chinese expose the same controls, states, error meaning, and accessibility labels.
- English status titles use `Codex 73% (1 reset)` or `Codex 73% (2 resets)`; Simplified Chinese uses `Codex 73%(2 次)`.
- Missing or zero reset data hides the status-title suffix in both languages.

## Error Handling

- Malformed protocol lines are ignored unless they correspond to a pending request.
- JSON-RPC errors are converted to short user-facing messages while preserving diagnostic detail for tests and stderr.
- A request timeout fails the operation without freezing the menu.
- Unexpected App Server termination fails pending requests, clears the process, and permits the next refresh to restart it.
- Authentication failures point the user to log in with the installed Codex client.
- Reset UI is disabled while a reset attempt is in flight.

## Security and Privacy

- Authentication remains owned by Codex App Server and the existing Codex credential store.
- The app does not read credential files or send tokens itself.
- Reset consumption is never automatic and always requires a visible confirmation.
- Reset identifiers remain in memory only for the current snapshot.
- The app communicates with a child process through local pipes; it does not open a listening network port.

## Testing Strategy

Development follows red-green-refactor for testable behavior.

Unit tests cover:

- Main-bucket selection and legacy fallback.
- Remaining-percentage clamping and rounding.
- Conditional reset-count formatting: zero or missing summaries hide the suffix, while positive counts append `(<count> 次)`.
- Decoding partial and multi-bucket responses.
- All reset outcomes and their display text.
- Last-reset persistence and decoding invalid stored data.
- Appearance selection, persistence, default system-following behavior, and menu checkmarks.
- English and Simplified Chinese copy parity, system-language resolution, manual override, runtime switching, and persistence.
- Idempotency-key reuse for one logical retry.
- JSON-RPC request/response matching and error propagation through an injectable transport.

Integration and build verification cover:

- A read-only `account/rateLimits/read` probe against the locally installed Codex CLI.
- The complete Swift test suite.
- A release build with `swift build -c release`.
- Packaging the release executable and `Info.plist` into `CodexUsage.app`.
- Ad-hoc code signing with `codesign`.
- Launching the packaged app, confirming the process remains alive, and then terminating only that launched test instance.

Automated verification must not consume an actual reset.

## Packaging

A repository script creates this layout under `dist/`:

```text
CodexUsage.app/
  Contents/
    Info.plist
    MacOS/CodexUsage
    Resources/
```

The minimum deployment target is macOS 13. The bundle identifier is `local.codexusage.menubar`. The generated `.app` is suitable for local use after ad-hoc signing; distribution to other Macs would require Developer ID signing and notarization, which are outside this task.

## Acceptance Criteria

- Launching `dist/CodexUsage.app` creates a menu bar item and no Dock icon.
- With the current zero-reset account snapshot, the title renders exactly as `Codex 100%` with no reset suffix.
- With available resets, the title renders in the agreed `Codex <remaining>%(x 次)` shape.
- Zero resets produces the exact disabled text **“当前没有可用 reset”**.
- A positive reset count enables a confirmed reset action.
- Reset attempts use an idempotency key, refresh usage afterward, and display the persisted latest time and result.
- The appearance submenu switches between Follow System, Light, and Dark, persists the choice, and does not alter the system-wide appearance.
- The language submenu switches between Follow System, English, and Simplified Chinese at runtime and persists the choice.
- `README.md` is the default English landing page; `README.zh-CN.md` contains the matching Simplified Chinese version, and both embed the selected light/dark design image and label unfinished functionality honestly.
- Network, authentication, protocol, and missing-binary errors remain visible and recoverable.
- All tests pass, the release binary compiles, the `.app` is signed, and the launch smoke test succeeds on the inspected Mac.
