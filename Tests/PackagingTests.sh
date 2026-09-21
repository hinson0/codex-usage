#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root"

scripts/build-app.sh >/dev/null

app="$repo_root/dist/CodexUsage.app"
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/CodexUsage"

[[ -d "$app" ]]
[[ -f "$info" ]]
[[ -x "$executable" ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$info")" == "local.codexusage.menubar" ]]
[[ "$(plutil -extract CFBundleExecutable raw "$info")" == "CodexUsage" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw "$info")" == "0.3.0" ]]
[[ "$(plutil -extract CFBundleVersion raw "$info")" == "3" ]]
[[ "$(plutil -extract LSUIElement raw "$info")" == "true" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw "$info")" == "13.0" ]]
codesign --verify --deep --strict "$app"

echo "Packaging checks passed: $app"
