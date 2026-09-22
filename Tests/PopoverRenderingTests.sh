#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --target CodexUsageCore >/dev/null
bin_dir="$(swift build --show-bin-path)"
output="${1:-$(mktemp -d "${TMPDIR:-/tmp}/codex-popover-render.XXXXXX")}"
mkdir -p "$output"
swiftc -parse-as-library -I "$bin_dir/Modules" \
  "$bin_dir/CodexUsageCore.build/"*.swift.o \
  Sources/CodexUsageApp/UsagePopoverView.swift TestsSupport/PopoverRendering.swift \
  -o "$output/PopoverRendering"
"$output/PopoverRendering" "$output"
