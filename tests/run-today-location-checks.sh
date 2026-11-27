#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/today-test-sources.sh
check_dir=$(mktemp -d /tmp/notchloom-today-location-checks.XXXXXX)
xcrun swiftc -parse-as-library "${today_sources[@]}" boringNotch/components/Notch/NotchShape.swift tests/TodayLocationPermissionTests.swift -o "$check_dir/checks"
"$check_dir/checks"
