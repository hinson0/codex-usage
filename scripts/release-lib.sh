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
