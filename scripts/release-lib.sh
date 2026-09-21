#!/bin/bash

release_short_version() {
  plutil -extract CFBundleShortVersionString raw "$1"
}

release_build_number() {
  plutil -extract CFBundleVersion raw "$1"
}

release_validate_semver() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

release_tag() {
  printf 'v%s\n' "$1"
}

release_asset_stem() {
  printf 'CodexUsage-v%s-macOS\n' "$1"
}

release_tag_is_present() {
  grep -Fxq "refs/tags/$1" <<<"$2"
}

release_require_private_key() {
  [[ -n "$1" ]] || {
    echo "SPARKLE_PRIVATE_KEY is required." >&2
    return 1
  }
}

release_validate_zip() (
  set -euo pipefail

  zip_path="$1"
  expected_version="$2"
  [[ -f "$zip_path" ]] || {
    echo "Release ZIP is missing: $zip_path" >&2
    exit 1
  }

  entries="$(zipinfo -1 "$zip_path")"
  [[ -n "$entries" ]] || {
    echo "Release ZIP is empty: $zip_path" >&2
    exit 1
  }

  while IFS= read -r entry; do
    case "$entry" in
      CodexUsage.app|CodexUsage.app/*) ;;
      *)
        echo "Unexpected top-level ZIP entry: $entry" >&2
        exit 1
        ;;
    esac
  done <<<"$entries"

  validation_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-zip-validation.XXXXXX")"
  trap 'rm -rf "$validation_root"' EXIT
  ditto -x -k "$zip_path" "$validation_root"

  info="$validation_root/CodexUsage.app/Contents/Info.plist"
  [[ -f "$info" ]] || {
    echo "Release ZIP does not contain CodexUsage.app metadata." >&2
    exit 1
  }

  actual_version="$(plutil -extract CFBundleShortVersionString raw "$info")"
  [[ "$actual_version" == "$expected_version" ]] || {
    echo "Release ZIP version $actual_version does not match $expected_version." >&2
    exit 1
  }
)
