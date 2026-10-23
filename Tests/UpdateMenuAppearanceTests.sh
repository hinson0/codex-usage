#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="$(mktemp -d "${TMPDIR:-/tmp}/codex-update-menu-test.XXXXXX")"
trap 'rm -rf "$output"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  Sources/CodexUsageApp/UpdateMenuAppearance.swift \
  TestsSupport/UpdateMenuAppearanceTests.swift -o "$output/UpdateMenuAppearanceTests"
"$output/UpdateMenuAppearanceTests"
