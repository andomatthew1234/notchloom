#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-/tmp/boringii-derived/Build/Products/Release/Notchloom.app}"

if [[ ! -d "$app_path" ]]; then
    print -u2 "Missing app: $app_path"
    exit 1
fi

app_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app_path/Contents/Info.plist")
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
output_path="${2:-$repo_root/dist/Notchloom-$app_version.dmg}"
if [[ "$app_name" != "Notchloom" ]]; then
    print -u2 "Expected a Notchloom app; found $app_name"
    exit 1
fi

codesign --verify --deep --strict "$app_path"
mkdir -p "${output_path:h}"
cd "$repo_root"
swift installer/render_background.swift installer/notchloom-background.png
uvx --from 'dmgbuild==1.6.7' dmgbuild \
    -s installer/dmg_settings.py \
    -D "app=$app_path" \
    -D "background=$repo_root/installer/notchloom-background.png" \
    -D "icon=$app_path/Contents/Resources/AppIcon.icns" \
    "Notchloom $app_version" "$output_path"

hdiutil verify "$output_path"
print "Created $output_path"
