#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root"

swift build -c release --product CodexUsage
bin_dir="$(swift build -c release --show-bin-path)"
source_binary="$bin_dir/CodexUsage"
source_info="$repo_root/Packaging/Info.plist"

[[ -x "$source_binary" ]] || { echo "Release executable is missing: $source_binary" >&2; exit 1; }
plutil -lint "$source_info" >/dev/null

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-package.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT

staged_app="$staging_root/CodexUsage.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
install -m 755 "$source_binary" "$staged_app/Contents/MacOS/CodexUsage"
install -m 644 "$source_info" "$staged_app/Contents/Info.plist"

codesign --force --sign - --timestamp=none "$staged_app"
codesign --verify --deep --strict "$staged_app"

mkdir -p "$repo_root/dist"
target_app="$repo_root/dist/CodexUsage.app"
if [[ -e "$target_app" ]]; then
  rm -rf "$target_app"
fi
mv "$staged_app" "$target_app"

echo "$target_app"
