#!/bin/bash

set -euo pipefail

readonly repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
readonly developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ -d "$developer_dir/Library/Developer/Frameworks/Testing.framework" ]]; then
  readonly frameworks_dir="$developer_dir/Library/Developer/Frameworks"
  readonly testing_libraries_dir="$developer_dir/Library/Developer/usr/lib"
else
  readonly frameworks_dir="$developer_dir/Library/Frameworks"
  readonly testing_libraries_dir="$developer_dir/usr/lib"
fi

run_shell_contract_tests() {
  "$repo_root/Tests/ReleaseScriptsTests.sh"
  "$repo_root/Tests/ReleaseArtifactsTests.sh"
  "$repo_root/Tests/ReleaseWorkflowTests.sh"
  if [[ "${CODEX_USAGE_SKIP_RUNNER_SCRIPT_TEST:-0}" != "1" ]]; then
    "$repo_root/Tests/TestRunnerScriptTests.sh"
  fi
}

if [[ ! -d "$frameworks_dir/Testing.framework" ]]; then
  swift test "$@"
  run_shell_contract_tests
  exit 0
fi

swift build --target CodexUsageCoreTests
bin_dir="$(swift build --show-bin-path)"
runner="$bin_dir/CodexUsageTestsRunner"
core_objects=("$bin_dir/CodexUsageCore.build/"*.swift.o)
test_objects=("$bin_dir/CodexUsageCoreTests.build/"*.swift.o)

swiftc \
  -parse-as-library \
  -F "$frameworks_dir" \
  -I "$bin_dir/Modules" \
  -L "$testing_libraries_dir" \
  -Xlinker -rpath -Xlinker "$frameworks_dir" \
  -Xlinker -rpath -Xlinker "$testing_libraries_dir" \
  -framework Testing \
  -l_TestingInterop \
  "${core_objects[@]}" \
  "${test_objects[@]}" \
  TestsSupport/TestRunner.swift \
  -o "$runner"

"$runner" "$@"

run_shell_contract_tests
