#!/bin/bash

set -euo pipefail

readonly frameworks_dir="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
readonly testing_libraries_dir="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ ! -d "$frameworks_dir/Testing.framework" ]]; then
  echo "Testing.framework was not found in Command Line Tools." >&2
  exit 1
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
