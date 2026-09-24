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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Tatami" "$app/Contents/MacOS/Tatami"
cp Resources/Info.plist "$app/Contents/Info.plist"
xattr -cr "$app"
# Set TATAMI_SIGN_IDENTITY (e.g. "Apple Development: ...") for a stable identity so Keychain access survives rebuilds.
codesign --force --deep --sign "${TATAMI_SIGN_IDENTITY:--}" "$app"
rm -rf dist/Tatami.app
mkdir -p dist
ditto "$app" dist/Tatami.app
codesign --verify --strict dist/Tatami.app
printf 'Built %s/dist/Tatami.app\n' "$PWD"
