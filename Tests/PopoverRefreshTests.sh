#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --target CodexUsageCore >/dev/null
bin_dir="$(swift build --show-bin-path)"
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" -I "$bin_dir/Modules" \
  "$bin_dir/CodexUsageCore.build/"*.swift.o \
  Sources/CodexUsageApp/UsagePopoverView.swift \
  Sources/CodexUsageApp/UpdateMenuAppearance.swift \
  TestsSupport/PopoverFixtures.swift TestsSupport/PopoverRefreshTests.swift \
  -o "$bin_dir/PopoverRefreshTests"
"$bin_dir/PopoverRefreshTests"
