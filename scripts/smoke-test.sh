#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
app="${1:-$repo_root/dist/CodexUsage.app}"
executable="$app/Contents/MacOS/CodexUsage"

[[ -x "$executable" ]] || { echo "App executable is missing: $executable" >&2; exit 1; }

runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-smoke.XXXXXX")"
smoke_pid=""

cleanup() {
  if [[ -n "$smoke_pid" ]] && kill -0 "$smoke_pid" 2>/dev/null; then
    kill "$smoke_pid" 2>/dev/null || true
    wait "$smoke_pid" 2>/dev/null || true
  fi
  rm -rf "$runtime_dir"
}
trap cleanup EXIT

"$executable" >"$runtime_dir/stdout.log" 2>"$runtime_dir/stderr.log" &
smoke_pid=$!

for _ in {1..20}; do
  if ! kill -0 "$smoke_pid" 2>/dev/null; then
    wait "$smoke_pid" || true
    sed -n '1,160p' "$runtime_dir/stderr.log" >&2
    echo "CodexUsage exited during smoke testing." >&2
    exit 1
  fi
  sleep 0.1
done

echo "Smoke test passed for PID $smoke_pid"
