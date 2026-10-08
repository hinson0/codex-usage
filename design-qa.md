# Codex Usage Design QA

## Reset Countdown (1.2.0, 2026-10-08)

- Scope: add the time remaining until the displayed reset below its existing timestamp. The screenshot's red box is an annotation, not UI. A separate line keeps the full date and positive reset count readable at the existing 348-point width. A local `TimelineView` updates the countdown every minute without issuing account requests.
- Source: the user's annotated screenshot, cropped to app-owned content in `docs/images/qa/codex-usage-countdown-reference.png`; the repository's `docs/images/codex-usage-dual-window.png` remains the broader hierarchy reference.
- Actual native evidence: `docs/images/qa/codex-usage-countdown-light-zh.png` and `docs/images/qa/codex-usage-countdown-dark-en.png`. Both use the production view in a real MenuBarExtra with synthetic usage and a no-network updater. The fixture shows 94% and `(1)`, while the source shows 100% and `(3)`; reset dates differ because fixture data is relative to capture time. Both are longer-window-only states with unlimited five-hour usage. The fixture omits the bundle version.
- Combined comparison: opened `docs/images/qa/codex-usage-countdown-comparison.png` and the focused `docs/images/qa/codex-usage-countdown-metadata-comparison.png`. Source content is 348 × 311 pixels; native implementation is 348 × 331 pixels at 1× density. The 20-point height increase is the intended countdown line, including native rounding. No density scaling was needed. Desktop chrome and annotation colors are outside the fidelity target.
- Fonts/typography: retained native SF sizes and weights, the 12.5-point secondary metadata style, and baseline-aligned reset count. Countdown digits are monospaced. Chinese and English dates, countdowns, percentages, and controls remain readable without truncation or unexpected wrapping.
- Spacing/layout rhythm: the countdown sits 4 points below the timestamp. The original horizontal date/count row, unlimited row, preferences, actions, dividers, and Quit row retain their spacing. The complete surface stays within the revised 335-point compact-height budget. Real-window checks retain a 2-point menu gap, attached shadow, and rounded corners through appearance/language switches, refresh, error expansion/recovery, and reopening.
- Colors/tokens: retained opaque white and native dark surfaces, blue progress, semantic foreground colors, and secondary reset metadata. The native status item remains under macOS contrast control.
- Image quality/assets: reused all existing native symbols and the status template icon. No new image assets or decorative elements were added to the App.
- Copy/content: Chinese uses `剩余 6天 3小时`; English uses `Time left: 6d 3h`. Short durations use hours/minutes, minutes, or less-than-one-minute copy. At or after the deadline, `等待重置` / `Reset pending` avoids claiming that an old snapshot has refreshed. Missing timestamps hide the countdown. Selection follows the same longer-window/five-hour fallback as the date.
- Verification: countdown tests first failed to compile because the new API did not exist, before production edits; focused tests then passed. The complete suite passes 41 registered tests (live integration skipped because no protocol code changed), four offscreen renders, release guards, and runner checks. All 18 native states pass with zero/10-point host padding and warm/slow refresh fixtures.
- Rendering-test correction: the first full run rejected transparent pixels at the raw capture's outer corners. The previous view passed; the new layout failed even with its timeline removed, while complete-frame and real-menu checks passed. `cacheDisplay` can include the native mask, so the test now verifies opacity at all four points inside the visible rounded surface, retaining the existing independent exterior-transparency, contrasting-backing, resize, shadow, and menu-anchor checks.
- No actionable P0/P1/P2 differences remain. Evidence limit: fixture captures establish this layout on the current desktop, not a live-account screenshot or coverage of every supported macOS release. Installed version and executable identity were checked separately.
- Package validation: `1.2.0 (22)` passes the release build with warnings as errors, packaging contracts, deep/strict signature verification, and packaged-app startup smoke test. No tag, push, or release was performed.
- Local installation: replaced `/Applications/CodexUsage.app` after user authorization and retained the previous `1.1.9` App in a temporary backup directory. The installed App reports `1.2.0 (22)`, its executable matches the verified package byte-for-byte, its signature passes deep/strict verification, and its process remains running after startup. The installed popover was not captured during this installation check.

final result: passed (native fixture and package verification)

## Detached Bottom Shadow (1.1.9, 2026-09-29)

- The user's white Chrome background exposes a second rounded white strip below the popover. Installed 1.1.8 has a 348 × 330 native frame around 348 × 310 content. Its layer mask removes the extra backing, but the compositor shadow still follows the larger frame: an approximately 10-point transparent gap separates the painted edge and shadow. Black backdrops and shadow-free window captures hid this defect in earlier checks.
- A white backing window and desktop-region capture now exercise the compositor shadow. Before production edits, `Tests/MenuBarPopoverRenderingTests.sh /tmp/codex-white-bottom-red --warm --slow` failed in the padded first-refresh state: `detached shadow below content (1.0 → 0.8635424971580505)`. The regression also requires shadow immediately below the content, so disabling the native shadow cannot pass.
- `ContentSizedPopover` preserves intrinsic content height, compensates for measured host padding, and fits the native frame to the content. It distinguishes content shrinkage from padding and explicitly resizes the window because older SDK compatibility behavior can retain the previous height. The appearance bridge observes changes to the surface and ancestor frames/bounds and reapplies its mask and 2-point menu anchor after layout settles.
- White-background evidence: `docs/images/qa/codex-usage-detached-shadow-before.png`, `docs/images/qa/codex-usage-attached-shadow-light-zh.png`, and `docs/images/qa/codex-usage-attached-shadow-dark-en.png`. The before image reproduces the original double contour. The after images show a single rounded edge with an attached fading shadow; text, action rows, preferences, reset count, and progress remain readable. The fixed compatibility fixture is 348 × 311 points, within the existing compact-height budget.
- Native checks cover zero/10-point host padding, initial loading or refresh, both appearances and languages, error expansion/recovery, and three reopens. `--warm` refreshes fixture data before opening; `--slow` keeps fixture reads in progress for 1.5 seconds. An additional executable with SDK compatibility metadata set to 15.5 exercises the older layout behavior; this is not an actual rebuild with the older compiler.
- Evidence limit: these are real MenuBarExtra fixture captures on the current macOS desktop, using synthetic usage data and a stub updater. They do not contact an account, consume a reset, establish behavior on every supported macOS release, or imply that the installed application has been updated.
- Validation passed: 36 real-menu states (18 current-SDK cold/slow states and 18 SDK-15.5-compatibility warm/slow states), with a 2-point menu gap throughout. `scripts/test.sh` passes 38 registered tests, four headless renders, release guards/workflow checks, and runner checks; the opt-in live integration test is skipped because no protocol code changed. The warnings-as-errors release build, packaging contracts, deep/strict signature verification, and packaged-app smoke test pass for `1.1.9 (21)`. No installation, tag, push, or release was performed.

final result: passed (local fixture and package verification)

## Icon and Bare Count (1.1.8, 2026-09-28)

- Accepted visual target: `docs/images/codex-usage-icon-count.png`. This scoped change replaces the menu-bar word `Codex` with the app's monochrome chevron/track mark and displays positive reset counts as `(1)` in both the status item and popover. Percentages, window ordering, zero-count hiding, reset time, and the existing compact popover layout remain intact.
- Evidence: `docs/images/qa/codex-usage-icon-count-status.png`, `docs/images/qa/codex-usage-icon-count-light-zh.png`, and `docs/images/qa/codex-usage-icon-count-dark-en.png`. Captured from a real MenuBarExtra using production `StatusItemContent` and `UsagePopoverView`, fixture usage of 94%, and one read-only reset. The fixture never starts Sparkle or contacts an account.
- Comparison: opened the accepted source and all three actual captures together in one visual comparison input, including a focused status-item capture. Source is 1586 × 992 with an approximately 620-pixel-wide popover; actual content is 348 × 306 at native 1× density, and the status crop is 88 × 22. Compared app-owned content and proportional hierarchy, not desktop wallpaper or the mock's enlarged native controls. The fixture date is September 27 rather than the concept's October 4; this is fixture data, not a formatting change.
- Fonts/typography: retained native SF hierarchy and baseline-aligned numeric text; no clipped count, title, or control text in either language.
- Spacing/layout: retained the existing 348-point compact surface and rounded corners. The status icon uses an 18 × 18 point image with native image/title spacing. The separate count fits the metadata row.
- Colors/tokens: native template rendering allows macOS to choose menu-bar contrast; the captured selected item is white on system blue. Popover appearance does not recolor the status item. White/dark surfaces, blue progress, and secondary metadata remain consistent.
- Asset fidelity: transparent raster template retains the approved chevron above a short bar, without a colored tile. Generated with built-in Image Gen from the approved concept and stored at `Sources/CodexUsageApp/Resources/StatusIconTemplate.png`; it is included in both SwiftPM resources and the packaged app. Generation brief: extract only the approved status icon, flat black silhouette with rounded strokes, true transparency, no text, tile, shadow, gradient, or other UI.
- Copy/content: visible status title is `94% (1)`, with `Codex` retained in its accessibility label. Popover count is `(1)` in English and Chinese; the existing next-reset timestamp label remains localized. Zero reset credits still produce no count.
- Verification: focused expectations failed against the old labels before production edits, then passed. Full suite: 38 tests, with the opt-in live protocol test skipped because no protocol code changed. Existing headless popover, release-script, and runner checks pass. Real MenuBarExtra checks pass all 18 states across zero/10-point padding, including loading, both languages, appearance changes, error growth/recovery, and reopening. The fixture also asserts the real NSStatusBarButton has the expected title and an 18-point template image.
- Main integration: retained the published 1.1.7 menu-anchor fix. Reran the complete suite and all 18 native states after synchronization; every state retained the 2-point menu gap. Refreshed the captures from this combined build.
- Release validation: version `1.1.8 (20)` builds with warnings as errors. Packaging contracts, deep/strict code-signature verification, and packaged-app smoke testing all pass.
- P3: the accepted concept enlarges controls and has different surrounding desktop chrome. The implementation intentionally retains established native metrics and existing popover layout; these are outside the requested icon/count change.
- No actionable P0/P1/P2 differences remain for this scope. These are fixture captures, not an installed upgrade or live-account screenshot.

final result: passed

## Menu-Bar Anchor Gap (1.1.7)

- The user's installed 1.1.6 screenshot shows a 12-point gap below the menu bar. The previous mask fixed the visible outline but left 10 points of transparent native padding inside the window, in addition to the normal 2-point menu gap. The earlier tests checked the isolated outline and did not measure its screen position relative to the menu bar.
- The appearance bridge now anchors the visible surface 2 points below the application's own status-button window on the same screen. It reapplies the position on layout, resize, and native window moves, with a reentrancy guard. The content mask continues to handle corners and native backing. No fixed 10-point inset or private AppKit class names are used by the fix.
- Added an independent screen-coordinate assertion to `Tests/MenuBarPopoverRenderingTests.sh`. Before the production change, the zero-inset case passed and the padded loading case failed with `empty strip below menu bar is 12.0 points; expected 0...2`. Afterward, all 18 states (zero/10-point host padding, loading, appearance/language changes, error expansion/recovery, and three reopens) measure a 2-point gap and retain the existing pixel checks.
- `docs/images/qa/codex-usage-menu-anchor-light-zh.png` includes the menu bar and the fixed padded fixture. A window-only crop is insufficient evidence for this regression.
- The full test suite, four offscreen rendering cases, warnings-as-errors release build, packaging/signature checks, and smoke test passed. The local 1.1.7 app was installed and started; its executable hash matches the verified build. The installed popup was closed during the final read-only process inspection, so the 2-point visual result above is established by the real-menu fixture, not an installed-app screenshot. Other macOS releases and multiple-display transitions have not been visually verified.

## Content-Aligned Native Mask (1.1.6)

- The user's 1.1.5 screenshot invalidates the earlier corner acceptance: the visible content still has square top corners and a strip of native backing below it.
- Read-only debugger inspection of the installed 1.1.5 process on macOS 26.6.2 found a 348 × 330 window with 348 × 310 painted content at y = 10. The old mask followed the entire 330-point frame, placing its rounded corners outside the actual content. The previous borderless host had no such padding and therefore missed this condition. Merely changing a test executable's SDK compatibility metadata did not reproduce the failure.
- The appearance bridge now occupies the complete SwiftUI background and converts that surface's bounds into native frame coordinates. The mask follows those bounds on layout and resize, clipping both the content and the native material outside it. No private AppKit class names or fixed system-padding values are used in production.
- `Tests/PopoverRenderingTests.sh` now covers both zero and 10-point vertical host padding in Light/Chinese and Dark/English. The padded cases failed before the fix with square content corners, visible native padding, and contrasting backing leakage. All four cases pass after the fix, including grow/shrink checks. This regression runs in the unfiltered `scripts/test.sh` suite.
- `Tests/MenuBarPopoverRenderingTests.sh` opens a real `MenuBarExtra`, uses fixture data and a stub updater, and checks compositor screenshots against an independent surface measurement. Both padding variants pass nine states each: loading, Light/Chinese, Dark/Chinese, Dark/English, error expansion, error recovery, and three reopens. Desktop focus changes can dismiss the test popover; the harness restores only its own window before capture. Screen Recording permission and a logged-in macOS desktop are required, so this test remains separate from headless CI.
- Real-window evidence: `docs/images/qa/codex-usage-content-mask-before.png`, `docs/images/qa/codex-usage-content-mask-light-zh.png`, and `docs/images/qa/codex-usage-content-mask-dark-en.png`. The before capture reproduces the measured native-padding geometry with unmodified 1.1.5 view code; the after captures use the fixed production view. These supersede the earlier borderless-window evidence for this defect.
- Evidence limit: these are local real-menu fixture captures on macOS 26.6.2, not a claim that every supported macOS release or the user's installed application has been upgraded. They omit the bundle version and live account state; installation/update delivery is separate from this visual verification.

## Native Window Corner Fringe (1.1.5)

- The user's screenshot of 1.1.4 shows gray system material around the content's rounded corners. The earlier content-only render missed this defect; the earlier passing result did not establish the complete popover outline.
- The content now paints an opaque rectangle, and a single shape mask clips the entire native window frame. This includes the system backing rather than exposing it around a separate SwiftUI clip. The mask follows window resize notifications so loading/error height changes are not clipped to the initial bounds.
- The regression harness inserts a contrasting red backing below the real content and renders the complete native frame layer tree. Before the fix, corner transparency and backing-color checks fail. With the fix, light Chinese and dark English pass both checks, plus interior opacity and grow/shrink checks.
- Current complete-frame captures: `docs/images/qa/codex-usage-window-mask-light-zh.png` and `docs/images/qa/codex-usage-window-mask-dark-en.png`. These supersede the content-only evidence for corner rendering. The render uses an inactive fixture host, so the progress bar is gray and the bundle version is absent.
- Evidence limit: this is a borderless NSWindow test host, not a captured MenuBarExtra window. CUA inspection of the installed app timed out. Real menu-bar chrome, shadow, and reopen/appearance-switch interaction remain unverified; no claim of installed-app visual acceptance is made.

## Rounded Surface and Compact Spacing (2026-09-22)

- Fixed the square opaque background by clipping the complete SwiftUI surface to a continuous 14-point rounded rectangle and clearing the popover window's backing fill. Interior content remains opaque in both appearances.
- Removed the redundant divider between preferences and actions, reduced their combined gap from 25 to 8 points, and trimmed section padding. Fixture content now measures 348 × 312 points, down from 348 × 341.
- Current renders: `docs/images/qa/codex-usage-rounded-compact-light-zh.png` and `docs/images/qa/codex-usage-rounded-compact-dark-en.png`. Both were inspected for corner shape, text clipping, and compact control spacing. The earlier evidence below describes previous layouts.
- `bash Tests/PopoverRenderingTests.sh` compiles the production view against fixture usage and a no-network updater. Before the fix, both appearances failed corner transparency, window backing, and compact-height checks. Afterward, both pass; interior opacity is also checked.
- Evidence limit: these are native NSHostingView renders, not screenshots of the installed menu-bar popup. The inactive host makes the progress bar gray and has no bundle version. Live window chrome, shadow, and menu interaction need an installed-app check.

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
- P3 evidence limit: the temporary QA window shows a keyboard focus ring, disables Sparkle's update action, and omits the bundle version because it is not the packaged app. These are harness artifacts. Packaging tests verify version `1.1.3 (15)`, and the production scene remains a single `MenuBarExtra`.
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

- Version-only verification release `1.1.3 (15)` allows installed `1.1.2` to detect a newer signed release and verify the green notice without clicking Check for Updates. No runtime or layout changes.
