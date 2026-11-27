#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/notchloom-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library BoringNotchXPCHelper/NotificationBannerReader.swift \
    tests/NotificationBannerReaderTests.swift -o "$check_dir/reader"
"$check_dir/reader"
sources=(boringNotch/NotificationPresentation.swift boringNotch/components/Notch/NotchShape.swift)
swiftc -parse-as-library "${sources[@]}" tests/NotificationPresentationTests.swift -o "$check_dir/checks"
"$check_dir/checks"
swiftc -parse-as-library "${sources[@]}" tests/NotchLayoutRegressionTests.swift -o "$check_dir/layout"
"$check_dir/layout"
swiftc -parse-as-library "${sources[@]}" tests/RenderNotificationSamples.swift -o "$check_dir/render"
"$check_dir/render" "$PWD/dist/notification-redesign"
