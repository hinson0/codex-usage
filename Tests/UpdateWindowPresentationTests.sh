#!/bin/bash
set -euo pipefail
# Requires a logged-in macOS desktop. No Screen Recording permission, live
# account, Sparkle check, or installed-app interaction is needed.
cd "$(dirname "$0")/.."
swift build --target CodexUsageCore >/dev/null
bin_dir="$(swift build --show-bin-path)"
output="$(mktemp -d "${TMPDIR:-/tmp}/codex-update-window-test.XXXXXX")"
trap 'rm -rf "$output"' EXIT
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos13.0" \
  -I "$bin_dir/Modules" "$bin_dir/CodexUsageCore.build/"*.swift.o \
  Sources/CodexUsageApp/UsagePopoverView.swift \
  Sources/CodexUsageApp/UpdateMenuAppearance.swift \
  Sources/CodexUsageApp/ContentSizedPopover.swift \
  TestsSupport/PopoverFixtures.swift TestsSupport/UpdateWindowPresentationTests.swift \
  -o "$output/UpdateWindowPresentationTests"
"$output/UpdateWindowPresentationTests"
