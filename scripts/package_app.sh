#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="dist/Tatami.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Tatami" "$app/Contents/MacOS/Tatami"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
printf 'Built %s/%s\n' "$PWD" "$app"
