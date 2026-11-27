#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/today-test-sources.sh
check_dir=$(mktemp -d /tmp/notchloom-today-briefing-checks.XXXXXX)
xcrun swiftc -parse-as-library "${today_sources[@]}" tests/TodayBriefingTests.swift -o "$check_dir/checks"
"$check_dir/checks"
if [[ "${1:-}" == "--live" ]]; then
    xcrun swiftc -parse-as-library "${today_sources[@]}" tests/TodayBriefingLiveTest.swift -o "$check_dir/live"
    "$check_dir/live"
fi
