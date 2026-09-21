#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$repo_root/scripts/release-lib.sh"

fixture="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-release-artifacts.XXXXXX")"
cleanup() {
  rm -rf "$fixture"
}
trap cleanup EXIT

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    echo "Expected failure: $*" >&2
    exit 1
  fi
}

[[ -x "$repo_root/scripts/package-release.sh" ]] || {
  echo "Release packager is missing" >&2
  exit 1
}
declare -F release_validate_zip >/dev/null || {
  echo "ZIP validator is missing" >&2
  exit 1
}

assert_fails env SPARKLE_PRIVATE_KEY= "$repo_root/scripts/package-release.sh" --validate-inputs

valid_app="$fixture/valid/CodexUsage.app"
mkdir -p "$valid_app/Contents"
cp "$repo_root/Packaging/Info.plist" "$valid_app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string 0.3.0 "$valid_app/Contents/Info.plist"
ditto -c -k --keepParent "$valid_app" "$fixture/valid.zip"
release_validate_zip "$fixture/valid.zip" "0.3.0"

wrong_app="$fixture/wrong/CodexUsage.app"
mkdir -p "$wrong_app/Contents"
cp "$repo_root/Packaging/Info.plist" "$wrong_app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string 0.2.9 "$wrong_app/Contents/Info.plist"
ditto -c -k --keepParent "$wrong_app" "$fixture/wrong.zip"
assert_fails release_validate_zip "$fixture/wrong.zip" "0.3.0"

multi_root="$fixture/multi"
mkdir -p "$multi_root/CodexUsage.app/Contents"
cp "$valid_app/Contents/Info.plist" "$multi_root/CodexUsage.app/Contents/Info.plist"
touch "$multi_root/unexpected.txt"
(cd "$multi_root" && ditto -c -k . "$fixture/extra.zip")
assert_fails release_validate_zip "$fixture/extra.zip" "0.3.0"

echo "Release artifact guard checks passed"
