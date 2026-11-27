#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/today-test-sources.sh
check_dir=$(mktemp -d /tmp/notchloom-today-context-checks.XXXXXX)
xcrun swiftc -parse-as-library "${today_sources[@]}" tests/TodayContextTests.swift -o "$check_dir/checks"
"$check_dir/checks"
