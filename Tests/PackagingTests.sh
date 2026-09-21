#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root"

scripts/build-app.sh >/dev/null

fail() {
  echo "$1" >&2
  exit 1
}

assert_equal() {
  [[ "$1" == "$2" ]] || fail "$3: expected '$2', got '$1'"
}

app="$repo_root/dist/CodexUsage.app"
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/CodexUsage"
framework="$app/Contents/Frameworks/Sparkle.framework"

[[ -d "$app" ]] || fail "Application bundle is missing"
[[ -f "$info" ]] || fail "Application Info.plist is missing"
[[ -x "$executable" ]] || fail "Application executable is missing"
[[ -d "$framework" ]] || fail "Embedded Sparkle framework is missing"
icon_name="$(plutil -extract CFBundleIconFile raw "$info")"
icon="$app/Contents/Resources/$icon_name"
assert_equal "$icon_name" "CodexUsage.icns" "Bundle icon name"
[[ -s "$icon" ]] || fail "Application icon is missing or empty"
iconset_check="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-icon-check.XXXXXX")"
trap 'rm -rf "$iconset_check"' EXIT
iconutil --convert iconset --output "$iconset_check/CodexUsage.iconset" "$icon" >/dev/null
[[ -s "$iconset_check/CodexUsage.iconset/icon_512x512@2x.png" ]] \
  || fail "Application icon is missing its 1024-pixel representation"
assert_equal "$(plutil -extract CFBundleIdentifier raw "$info")" "local.codexusage.menubar" "Bundle identifier"
assert_equal "$(plutil -extract CFBundleExecutable raw "$info")" "CodexUsage" "Bundle executable"
assert_equal "$(plutil -extract CFBundleShortVersionString raw "$info")" "1.1.3" "Short version"
assert_equal "$(plutil -extract CFBundleVersion raw "$info")" "15" "Build number"
assert_equal "$(plutil -extract LSUIElement raw "$info")" "true" "Menu-bar-only flag"
assert_equal "$(plutil -extract LSMinimumSystemVersion raw "$info")" "13.0" "Minimum macOS version"
[[ -n "$(plutil -extract SUFeedURL raw "$info")" ]] || fail "Sparkle feed URL is empty"
public_key="$(plutil -extract SUPublicEDKey raw "$info")"
assert_equal "$(printf '%s' "$public_key" | base64 -D | wc -c | tr -d ' ')" "32" "Sparkle public-key byte count"
assert_equal "$(plutil -extract SUEnableAutomaticChecks raw "$info")" "true" "Automatic update checks"
assert_equal "$(plutil -extract SUAutomaticallyUpdate raw "$info")" "false" "Unattended update installation"
assert_equal "$(plutil -extract SUVerifyUpdateBeforeExtraction raw "$info")" "true" "Pre-extraction verification"
otool -L "$executable" | grep -Fq '@rpath/Sparkle.framework/' \
  || fail "Executable does not link Sparkle through @rpath"
otool -l "$executable" | grep -Fq '@loader_path/../Frameworks' \
  || fail "Executable is missing the embedded-framework rpath"
codesign --verify --deep --strict "$framework" \
  || fail "Embedded Sparkle signature is invalid"
codesign --verify --deep --strict "$app" \
  || fail "Application signature is invalid"

echo "Packaging checks passed: $app"
