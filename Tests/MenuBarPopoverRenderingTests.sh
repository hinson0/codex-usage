#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product CodexUsage >/dev/null
bin_dir="$(swift build --show-bin-path)"
output="${1:-$(mktemp -d "${TMPDIR:-/tmp}/codex-menubar-render.XXXXXX")}"
if [[ $# -gt 0 ]]; then shift; fi
mkdir -p "$output"
output="$(cd "$output" && pwd -P)"
swiftc -O -parse-as-library -swift-version 6 \
  -target "$(uname -m)-apple-macos13.0" \
  -I "$bin_dir/Modules" "$bin_dir/CodexUsageCore.build/"*.swift.o \
  Sources/CodexUsageApp/UsagePopoverView.swift \
  Sources/CodexUsageApp/UpdateMenuAppearance.swift \
  Sources/CodexUsageApp/ContentSizedPopover.swift \
  Sources/CodexUsageApp/StatusItemContent.swift \
  "$bin_dir/CodexUsage.build/DerivedSources/resource_bundle_accessor.swift" \
  TestsSupport/PopoverFixtures.swift TestsSupport/MenuBarPopoverRendering.swift \
  -o "$output/MenuBarPopoverRendering"

# Requires a logged-in macOS desktop with Accessibility and Screen Recording
# access. It clicks its own fixture item; it never accesses the live account.
for inset in 0 10; do
  "$output/MenuBarPopoverRendering" "$inset" "$output" "$@"
done
