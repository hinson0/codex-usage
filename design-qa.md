# Codex Usage Design QA

## Evidence

- Source visual truth: `docs/images/codex-usage-dual-window.png`.
- Rendered implementation: `docs/images/qa/codex-usage-actual-opaque-light-zh.png`.
- Normalized side-by-side comparison: `docs/images/qa/codex-usage-source-vs-actual.png`.
- Source pixels: 1586 × 992. The popover crop was 610 × 585 and normalized to 348 × 334.
- Implementation pixels: 348 × 367. The app-content crop below the QA title bar was 348 × 337.
- Density normalization: both content crops were compared at 348 px wide. The three-pixel height difference is native window rounding and action-row metrics.
- State: Light appearance, Simplified Chinese, live `codex` account with a longer window, no five-hour window, and zero reset credits. Live remaining usage changed from the mock's 94% to 88% during capture.

## Full-view Comparison

The implementation keeps the approved hierarchy: `Codex 剩余`, the longer-window percentage and blue progress bar, reset time, the `5 小时剩余 / 无限制` row, two-cell preferences, a single horizontal refresh/update row, and a separate Quit row. The reset redemption button, confirmation, empty state, and local history block are absent. Auxiliary buckets remain absent.

The menu-bar title was also observed against the live account as a single percentage when no five-hour window exists. Automated presentation coverage verifies the dual-window form as `Codex x%-y%`, ordered by window duration rather than primary/secondary response slot.

## Focused-region Comparison

The normalized side-by-side image compares the complete app-owned content at the same 348 px width, so no extra focused crop was needed. Text, progress, metadata, preferences, actions, dividers, and bottom spacing are all readable in that comparison.

## Required Fidelity Surfaces

- Fonts and typography: both use native SF typography with the same weight hierarchy. The implementation uses native control metrics and is optically smaller than the generated mock, but remains readable with no clipping or unwanted wrapping.
- Spacing and layout rhythm: the implementation matches the target's compact 348-point width and 337-point content height. Section padding, dividers, equal-width preference cells, equal-width action cells, and the standalone Quit row align with the target.
- Colors and visual tokens: system blue is reserved for the progress bar. Light appearance now uses an explicit opaque white content background, while Dark retains the native window background. Semantic text, subtle tinted control rows, and separators preserve contrast without the foreground app bleeding through.
- Image quality and asset fidelity: the screen contains no raster content assets. Native SF Symbols are used for utility controls; no placeholder, emoji, custom SVG, or code-drawn asset substitutes are present.
- Copy and content: the captured unlimited state uses the approved Chinese copy. Positive reset count is absent at zero; dual-window percentages and localized reset suffixes are covered by focused tests.

## Findings

- No actionable P0, P1, or P2 findings remain.
- P3: the generated mock uses slightly larger display typography than native macOS controls. Keeping native metrics avoids cramped labels and preserves platform consistency.
- P3 evidence limit: the temporary QA window shows a keyboard focus ring, disables Sparkle's update action, and omits the bundle version because it is not the packaged app. These are harness artifacts. Packaging tests verify version `1.1.2 (14)`, and the production scene remains a single `MenuBarExtra`.
- The live account has no five-hour window, so the finite `x% - y%` popover state was not visually captured. Unit tests cover both window orders, missing percentages, duplicate 300-minute windows, and longer-window progress/reset selection.

## Comparison History

- Preference centering correction: the Appearance and Language menus now use their intrinsic horizontal size inside equal-width cells. Removed the expanding gap in their labels, retaining the native dropdown indicators. Verified the actual SwiftUI view in `docs/images/qa/codex-usage-centered-preferences-zh.png` (348 × 341 points, Light/Simplified Chinese, fixture usage 84%). Both icon/text/indicator groups are centered in their respective halves, matching the action row below. This isolated AppKit render uses an inactive window (gray progress tint), a stub updater, and no bundle version; it verifies layout rather than live account or updater behavior.

1. Baseline: the old UI devoted a full section to reset redemption, zero-reset copy, and locally stored history.
2. Selected redesign: removed reset operations/history, moved positive reset count beside the reset time, added the unlimited five-hour row, and placed Refresh/Update side by side.
3. Code-review iteration: fixed longer-window progress fallback and duplicate 300-minute-window classification, then added duration-order regression coverage.
4. Background regression: the production `MenuBarExtra` material allowed a dark foreground app to tint Light appearance gray. The root view now paints opaque white in Light and an opaque native window color in Dark.
5. Post-fix evidence: `docs/images/qa/codex-usage-source-vs-actual.png` shows the final unlimited state aligned with the target; the white content remains opaque against a black QA host.

## Verification Scope

- Visually verified: opaque-white Light/Simplified Chinese content, live longer-window percentage and reset time, unlimited five-hour row, hidden zero reset count, compact preferences, horizontal actions, and Quit separation.
- Verified by automated tests: light/dark background policy, five-hour-first title formatting, response-slot independence, single-window fallback, longer-window progress/reset selection, reset singular/plural copy, hidden zero count, localization parity, legacy reset-history deletion, and read-only live integration.
- Verified structurally: no reset consume RPC, idempotency key, reset credit identifier, redemption action, or reset-history model/persistence remains in application code.

## Final Result

final result: passed

## Update Availability Label (2026-09-21)

- The existing update action displays `有新版本` / `Update Available` after Sparkle reports a valid update; otherwise it displays the existing localized check action.
- A successful check with no valid update clears the indicator. Transient check failures retain the last known result. The label is independent of usage loading/errors and button enablement.
- Layout, icon, and installation confirmation behavior are unchanged. Automated presentation tests cover both languages and enabled/disabled states. This text-only change has not received a new screenshot capture; the images above document the previous default state.

- Version-only verification release: `1.1.1 (13)` provides a newer signed update for manually checking the indicator from installed `1.1.0`; no UI or runtime logic changes.

## Automatic Green Update Notice

- Corrected the intended behavior: startup, popover opening, and an independent five-hour task silently probe Sparkle for updates. Probes skip an active Sparkle session and do not depend on usage refresh completion.
- Available updates display green `新版本` / `New Version`; the default action retains its normal color. Clicking still opens Sparkle's interactive update flow.
- This supersedes the earlier availability-label wording. Existing screenshots predate this change; automated tests verify localized text but do not establish rendered color or live feed behavior.
