#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-test-runner.XXXXXX")"
cleanup() {
  rm -rf "$fixture"
}
trap cleanup EXIT

fake_developer_dir="$fixture/Xcode.app/Contents/Developer"
fake_bin="$fixture/bin"
marker="$fixture/swift-arguments"
mkdir -p "$fake_developer_dir" "$fake_bin"

cat > "$fake_bin/swift" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" > "$CODEX_USAGE_SWIFT_MARKER"
SCRIPT
chmod +x "$fake_bin/swift"

PATH="$fake_bin:$PATH" \
DEVELOPER_DIR="$fake_developer_dir" \
CODEX_USAGE_SWIFT_MARKER="$marker" \
CODEX_USAGE_SKIP_RUNNER_SCRIPT_TEST=1 \
  "$repo_root/scripts/test.sh" --filter PortableFallback

[[ "$(<"$marker")" == "test --filter PortableFallback" ]] || {
  echo "Full-Xcode fallback did not invoke swift test with the original arguments." >&2
  exit 1
}

echo "Test runner portability checks passed"
