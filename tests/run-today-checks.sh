#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/notchloom-today-checks.XXXXXX)
xcrun swiftc -D DEBUG -parse-as-library \
  boringNotch/Intelligence/TodayReport.swift \
  boringNotch/Intelligence/TodayPresentation.swift \
  boringNotch/Intelligence/TodayPreviewContent.swift \
  boringNotch/Intelligence/TodayInlineText.swift \
  boringNotch/Intelligence/TodayPageView.swift \
  boringNotch/extensions/PanGesture.swift \
  boringNotch/components/Notch/TodayWidget.swift \
  boringNotch/components/Notch/NotchShape.swift \
  tests/TodayMotionReview.swift \
  tests/TodayPresentationTests.swift -o "$check_dir/checks"
"$check_dir/checks"
