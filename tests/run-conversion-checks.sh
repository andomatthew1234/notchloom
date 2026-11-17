#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
binary="/tmp/notchloom-convert-check"

cd "$repo_root"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
    boringNotch/components/Shelf/Convert/ConversionModels.swift \
    boringNotch/components/Shelf/Convert/ConversionEngines.swift \
    boringNotch/components/Shelf/Convert/FFmpegConversionEngine.swift \
    boringNotch/components/Shelf/Convert/TextUtilConversionEngine.swift \
    boringNotch/components/Shelf/Convert/ArchiveConversionEngine.swift \
    tests/ConversionEngineSmoke.swift -o "$binary"
"$binary"
