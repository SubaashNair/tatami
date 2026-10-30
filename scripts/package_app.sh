#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
# iCloud Drive (e.g. ~/Documents) re-adds Finder metadata that codesign rejects, so assemble and sign outside the project.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
app="$staging/Tatami.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$binary_dir/Tatami" "$app/Contents/MacOS/Tatami"
# The `tatami` command lives in Helpers, not MacOS: file names ignore case on macOS, so tatami would replace Tatami.
cp "$binary_dir/tatami-cli" "$app/Contents/Helpers/tatami"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
xattr -cr "$app"
# Set TATAMI_SIGN_IDENTITY (e.g. "Apple Development: ...") for a stable identity so Keychain access survives rebuilds.
identity="${TATAMI_SIGN_IDENTITY:--}"
codesign --force --sign "$identity" "$app/Contents/Helpers/tatami"  # nested code is signed first, then the app
codesign --force --deep --sign "$identity" "$app"
rm -rf dist/Tatami.app
mkdir -p dist
ditto "$app" dist/Tatami.app
codesign --verify --strict dist/Tatami.app
printf 'Built %s/dist/Tatami.app\n' "$PWD"
