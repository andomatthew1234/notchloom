#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/notchloom-power-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cat > "$check_dir/ViewModelStub.swift" <<'STUB'
import Combine
@MainActor final class BoringViewModel: ObservableObject { @Published var isBatteryPopoverActive = false }
STUB
xcrun swiftc -parse-as-library "$check_dir/ViewModelStub.swift" boringNotch/Power/*.swift tests/PowerUsageTests.swift -o "$check_dir/checks"
"$check_dir/checks" "$@"
