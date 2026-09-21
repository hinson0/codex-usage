#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$repo_root/scripts/release-lib.sh"

fixture="$(mktemp "${TMPDIR:-/tmp}/codex-usage-release-plist.XXXXXX")"
cleanup() {
  rm -f "$fixture"
}
trap cleanup EXIT

cp "$repo_root/Packaging/Info.plist" "$fixture"
plutil -replace CFBundleShortVersionString -string 9.8.7 "$fixture"
plutil -replace CFBundleVersion -string 42 "$fixture"

assert_equal() {
  [[ "$1" == "$2" ]] || {
    echo "Expected '$2', got '$1'" >&2
    exit 1
  }
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    echo "Expected failure: $*" >&2
    exit 1
  fi
}

assert_equal "$(release_short_version "$fixture")" "9.8.7"
assert_equal "$(release_build_number "$fixture")" "42"
release_validate_semver "0.3.0"
assert_fails release_validate_semver "0.3"
assert_fails release_validate_semver "v0.3.0"
assert_equal "$(release_tag 0.3.0)" "v0.3.0"
assert_equal "$(release_asset_stem 0.3.0)" "CodexUsage-v0.3.0-macOS"
release_tag_is_present "v0.3.0" $'refs/tags/v0.2.0\nrefs/tags/v0.3.0'
assert_fails release_tag_is_present "v0.4.0" $'refs/tags/v0.2.0\nrefs/tags/v0.3.0'
assert_fails release_require_private_key ""
release_require_private_key "test-only-key"

echo "Release script checks passed"
