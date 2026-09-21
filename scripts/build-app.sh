#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root"

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-package.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT

swift_build_arguments=(-c release --product CodexUsage)
source_info="$repo_root/Packaging/Info.plist"

if [[ "${CODEX_USAGE_UNIVERSAL:-0}" == "1" ]]; then
  arm64_scratch="$repo_root/.build/codex-usage-arm64"
  x86_64_scratch="$repo_root/.build/codex-usage-x86_64"

  swift build --scratch-path "$arm64_scratch" "${swift_build_arguments[@]}" --arch arm64
  arm64_bin_dir="$(swift build --scratch-path "$arm64_scratch" "${swift_build_arguments[@]}" --arch arm64 --show-bin-path)"

  swift build --scratch-path "$x86_64_scratch" "${swift_build_arguments[@]}" --arch x86_64
  x86_64_bin_dir="$(swift build --scratch-path "$x86_64_scratch" "${swift_build_arguments[@]}" --arch x86_64 --show-bin-path)"

  source_binary="$staging_root/CodexUsage"
  lipo -create \
    "$arm64_bin_dir/CodexUsage" \
    "$x86_64_bin_dir/CodexUsage" \
    -output "$source_binary"
  artifact_root="$arm64_scratch/artifacts"
else
  swift build "${swift_build_arguments[@]}"
  bin_dir="$(swift build "${swift_build_arguments[@]}" --show-bin-path)"
  source_binary="$bin_dir/CodexUsage"
  artifact_root="$repo_root/.build/artifacts"
fi

sparkle_frameworks=()
while IFS= read -r candidate; do
  sparkle_frameworks+=("$candidate")
done < <(find "$artifact_root" -type d -name Sparkle.framework -print)

[[ -x "$source_binary" ]] || { echo "Release executable is missing: $source_binary" >&2; exit 1; }
[[ "${#sparkle_frameworks[@]}" -eq 1 ]] || {
  echo "Expected one resolved Sparkle.framework, found ${#sparkle_frameworks[@]}." >&2
  exit 1
}
plutil -lint "$source_info" >/dev/null

staged_app="$staging_root/CodexUsage.app"
mkdir -p \
  "$staged_app/Contents/Frameworks" \
  "$staged_app/Contents/MacOS" \
  "$staged_app/Contents/Resources"
install -m 755 "$source_binary" "$staged_app/Contents/MacOS/CodexUsage"
install -m 644 "$source_info" "$staged_app/Contents/Info.plist"
ditto "${sparkle_frameworks[0]}" "$staged_app/Contents/Frameworks/Sparkle.framework"

codesign --force --deep --sign - --timestamp=none "$staged_app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none "$staged_app"
codesign --verify --deep --strict "$staged_app"

mkdir -p "$repo_root/dist"
target_app="$repo_root/dist/CodexUsage.app"
if [[ -e "$target_app" ]]; then
  rm -rf "$target_app"
fi
mv "$staged_app" "$target_app"

echo "$target_app"
