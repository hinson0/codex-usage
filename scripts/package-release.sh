#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$repo_root/scripts/release-lib.sh"
cd "$repo_root"

private_key="${SPARKLE_PRIVATE_KEY:-}"
release_require_private_key "$private_key"

swift package resolve >/dev/null
generate_appcast="$(find "$repo_root/.build" -type f -name generate_appcast -perm -111 -print -quit)"
sign_update="$(find "$repo_root/.build" -type f -name sign_update -perm -111 -print -quit)"
[[ -x "$generate_appcast" ]] || {
  echo "Sparkle generate_appcast tool was not found." >&2
  exit 1
}
[[ -x "$sign_update" ]] || {
  echo "Sparkle sign_update tool was not found." >&2
  exit 1
}

if [[ "${1:-}" == "--validate-inputs" ]]; then
  exit 0
fi
[[ "$#" -eq 0 ]] || {
  echo "Usage: scripts/package-release.sh [--validate-inputs]" >&2
  exit 1
}

info="$repo_root/Packaging/Info.plist"
version="$(release_short_version "$info")"
build_number="$(release_build_number "$info")"
release_validate_semver "$version" || {
  echo "Invalid release version: $version" >&2
  exit 1
}
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || {
  echo "Invalid release build number: $build_number" >&2
  exit 1
}

tag="$(release_tag "$version")"
asset_stem="$(release_asset_stem "$version")"
release_dir="$repo_root/dist/release"
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-release.XXXXXX")"
mount_point="$staging_root/mount"
is_mounted=0

cleanup() {
  if [[ "$is_mounted" == "1" ]]; then
    hdiutil detach -quiet "$mount_point" >/dev/null 2>&1 || true
  fi
  rm -rf "$staging_root"
}
trap cleanup EXIT

CODEX_USAGE_UNIVERSAL=1 "$repo_root/scripts/build-app.sh" >/dev/null

if [[ -e "$release_dir" ]]; then
  rm -rf "$release_dir"
fi
mkdir -p "$release_dir"

zip_path="$release_dir/$asset_stem.zip"
dmg_path="$release_dir/$asset_stem.dmg"
appcast_path="$release_dir/appcast.xml"

ditto -c -k --keepParent "$repo_root/dist/CodexUsage.app" "$zip_path"
release_validate_zip "$zip_path" "$version"

dmg_root="$staging_root/dmg"
mkdir -p "$dmg_root"
ditto "$repo_root/dist/CodexUsage.app" "$dmg_root/CodexUsage.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create \
  -quiet \
  -volname "Codex Usage" \
  -srcfolder "$dmg_root" \
  -format UDZO \
  "$dmg_path"

updates_root="$staging_root/updates"
mkdir -p "$updates_root"
ditto "$zip_path" "$updates_root/$(basename "$zip_path")"
printf '%s' "$private_key" | "$generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/hinson0/codex-usage/releases/download/$tag/" \
  --link "https://github.com/hinson0/codex-usage" \
  -o "$updates_root/appcast.xml" \
  "$updates_root" >/dev/null
[[ -f "$updates_root/appcast.xml" ]] || {
  echo "Sparkle did not generate appcast.xml." >&2
  exit 1
}
install -m 644 "$updates_root/appcast.xml" "$appcast_path"

signature="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$appcast_path")"
[[ -n "$signature" ]] || {
  echo "The appcast enclosure is missing an EdDSA signature." >&2
  exit 1
}
printf '%s' "$private_key" | "$sign_update" \
  --verify \
  --ed-key-file - \
  "$zip_path" \
  "$signature" >/dev/null

(
  cd "$release_dir"
  LC_ALL=C shasum -a 256 \
    "$(basename "$dmg_path")" \
    "$(basename "$zip_path")" \
    "$(basename "$appcast_path")" \
    | sort -k2 > SHA256SUMS
)

mkdir -p "$mount_point"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mount_point" "$dmg_path"
is_mounted=1
[[ -d "$mount_point/CodexUsage.app" ]]
[[ -L "$mount_point/Applications" ]]
[[ "$(readlink "$mount_point/Applications")" == "/Applications" ]]
hdiutil detach -quiet "$mount_point"
is_mounted=0

printf '%s\n' \
  "$dmg_path" \
  "$zip_path" \
  "$appcast_path" \
  "$release_dir/SHA256SUMS"
