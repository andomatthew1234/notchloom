#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/notchloom-gemini-checks.XXXXXX)
sources=(boringNotch/Intelligence/GeminiCredentialStore.swift
         boringNotch/Intelligence/GeminiClient.swift
         boringNotch/Intelligence/TodayReport.swift
         boringNotch/Intelligence/GeminiModelStore.swift)
xcrun swiftc -parse-as-library "${sources[@]}" tests/GeminiPhaseOneTests.swift -o "$check_dir/checks"
"$check_dir/checks"
if [[ "${1:-}" == "--live" ]]; then
    # Deliberately opt-in: never inspect ordinary Google keys or app Keychain credentials.
    xcrun swiftc -parse-as-library "${sources[@]}" tests/GeminiLiveConnectionTest.swift -o "$check_dir/live"
    "$check_dir/live"
fi
