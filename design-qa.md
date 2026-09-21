# Codex Usage Design QA

## Evidence

- Source visual truth: `docs/images/codex-usage-compact-no-system.png`
- Light implementation: `docs/images/qa/codex-usage-actual-light-zh.png`
- Dark implementation: `docs/images/qa/codex-usage-actual-dark-en.png`
- Combined comparison: `docs/images/qa/codex-usage-target-vs-actual.png`
- Source pixels: 1586 × 992 at 1×. Source popover crops are approximately 475 × 450 (light) and 481 × 450 (dark).
- Implementation pixels: 348 × 379 panel crops at 1×, captured from a 1920 × 1080 macOS desktop.
- Normalization: source and implementation panel crops were each resized to 450 px wide before side-by-side comparison.
- State: primary Codex usage at 98%, zero resets, no auxiliary quota rows. Light/Simplified Chinese and Dark/English appearances were both captured.

## Full-view Comparison

The implemented panel preserves the selected compact hierarchy: title and percentage, horizontal progress bar, next-reset line, reset empty state, full-width two-cell preferences footer, then refresh and quit. `gpt-reserve` and all auxiliary quota buckets are absent. Both Follow System choices are absent.

The implementation uses the native menu-bar window material and SF Symbols. Its 348 × 379 footprint is close to the original prototype's approximately 340 × 363 footprint and materially smaller than the rejected 432-point implementation.

## Focused-region Comparison

Focused comparison was required for the preferences footer and appearance behavior:

- The footer now spans the content width and splits evenly between Appearance and Language.
- Light and Dark are the only appearance choices; English and Simplified Chinese are the only language choices.
- The dark capture visibly uses a dark native panel, controls, and light foreground text.
- The light capture visibly uses a light native panel and dark foreground text.
- English is the default for fresh or migrated legacy-system preferences; the Chinese capture verifies runtime switching.

## Required Fidelity Surfaces

- Fonts and typography: native SF typography, hierarchy, weights, and truncation match the compact target. The implementation's native control text is slightly optically smaller than ImageGen text but remains readable and balanced.
- Spacing and layout rhythm: 348-point width, compact insets, centered empty state, full-width preferences footer, and action rows are aligned. Native menu metrics make the panel slightly taller than the generated reference; this is classified as P3.
- Colors and visual tokens: restrained system blue, native light/dark materials, semantic secondary text, and separators match the target. Contrast is visibly sufficient in both captured states.
- Image and icon fidelity: there are no raster content assets. Controls use native SF Symbols rather than approximated icons.
- Copy and content: English and Simplified Chinese are correct for the captured states. No Follow System copy, `gpt-reserve`, model name, secondary quota, or invented metric is visible.

## App Icon QA

- Selected direction: a terminal chevron paired with a three-quarter usage bar, matching the app's developer-tool purpose and system-blue progress treatment without copying the OpenAI or ChatGPT mark.
- Source artwork: `Packaging/CodexUsageIcon-1024.png`, 1024 × 1024 RGBA with transparency outside the macOS squircle.
- Packaged artwork: `Packaging/CodexUsage.icns`, containing the standard 16, 32, 128, 256, 512, and 1024-pixel representations.
- Small-size check: the chevron and filled-versus-unfilled bar remain distinct at 32 × 32; there is no text or fine linework that collapses at Spotlight and Finder sizes.
- Bundle check: `CFBundleIconFile` points to `CodexUsage.icns`, the build copies it into `Contents/Resources`, and packaging verification expands the ICNS and confirms the 1024-pixel representation.

## Comparison History

1. Initial implementation: auxiliary `gpt-reserve` row, undersized typography, narrow layout, and abruptly centered preference controls. Dark selection did not visibly change the panel.
2. Integrated-footer iteration: removed auxiliary quotas, widened hierarchy, and created a two-cell footer. QA still found an oversized 432-point panel and ineffective dark appearance.
3. Final iteration: removed both Follow System options, migrated defaults to Light and English, forced the selected native appearance on the app and menu-bar window, reduced width to 348 points, restored compact type and spacing, and retained the full-width footer.
4. Status-item correction: a user-reported regression showed that application-wide appearance also recolored the menu-bar title. Appearance is now scoped only to the popover window; the status item remains system-controlled. The scope contract is covered by `appearanceSelectionIsScopedToPopoverInsteadOfWholeApplication`.
5. Local-history iteration: the single latest-reset line became a compact history block showing at most three app-recorded attempts, newest first. The zero-history state keeps the original centered empty copy; populated rows are one line each and scale down slightly before truncating.

## Findings

- No actionable P0, P1, or P2 findings remain.
- P3: native macOS row metrics make the implementation about 16 px taller than a purely proportional rendering of the generated reference. Further compression would reduce hit targets and fight native control sizing, so it is intentionally retained.
- P3: a populated three-row local history makes the panel taller than the zero-history reference. The list is deliberately capped at three rows to keep the menu compact.

## Interaction and Evidence Limits

- Verified visually: Light, Dark, English, Simplified Chinese, zero-reset state, hidden auxiliary quotas, and compact layout.
- Verified structurally and by regression test: popover appearance never sets application-level appearance, so the menu-bar title remains under macOS contrast control.
- Verified by automated tests: positive-reset title/action behavior, confirmation state, localization parity, three-record ordering and cap, single-record migration, and persistence.
- Not visually exercised because the live account has zero resets: the positive-reset confirmation button and populated three-row local-history state.

## Final Result

final result: passed
