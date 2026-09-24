#!/bin/bash
# Opt-in integration test for window parking (M1 decision 16).
# Needs Accessibility for the terminal (or agent) running it; it drives TextEdit and Tatami's global shortcuts.
# Uses an isolated data directory, so your real Tatami settings are untouched. Close TextEdit first.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
data="$work/data"; mkdir -p "$data"
probe="$work/ax_probe"
tatami_pid=""
failures=0

cleanup() {
    [ -n "$tatami_pid" ] && kill -TERM "$tatami_pid" 2>/dev/null || true
    osascript -e 'tell application "TextEdit" to close every document saving no' -e 'tell application "TextEdit" to quit' >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

if pgrep -xq TextEdit; then echo "Quit TextEdit before running this test."; exit 1; fi
if pgrep -xq Tatami; then echo "Quit Tatami before running this test."; exit 1; fi
if pgrep -xq AeroSpace || pgrep -xq yabai || pgrep -xq Amethyst; then echo "Quit your tiling window manager (AeroSpace, yabai, Amethyst) before running this test; it resizes the test windows."; exit 1; fi

swiftc -O -o "$probe" scripts/ax_probe.swift
bash scripts/package_app.sh debug >/dev/null

key() { osascript -e "tell application \"System Events\" to key code $1 using {$2}"; sleep 1; }
state_of() { "$probe" TextEdit | awk -F'\t' -v t="$1" '$2 == t { print $1 }'; }
expect() {  # expect <title> <state> <label>
    local actual; actual="$(state_of "$1")"
    if [ "$actual" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: '$1' is '$actual', expected '$2'"; failures=$((failures + 1)); fi
}
expect_frame() {  # expect_frame <title> <"x,y wxh"> <label>
    local actual; actual="$("$probe" TextEdit | awk -F'\t' -v t="$1" '$2 == t { print $3 }')"
    if [ "$actual" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: '$1' at '$actual', expected '$2'"; failures=$((failures + 1)); fi
}
focus_doc() { osascript -e 'tell application "TextEdit" to activate' -e "tell application \"TextEdit\" to set index of window \"$1\" to 1"; sleep 1; }
launch_tatami() {
    TATAMI_DATA_DIR="$data" TATAMI_AUTOSTART="$1" TATAMI_ONLY_BUNDLES=com.apple.TextEdit dist/Tatami.app/Contents/MacOS/Tatami >/dev/null 2>&1 &
    tatami_pid=$!
    sleep 3
}

echo "Setting up TextEdit windows"
osascript -e 'tell application "TextEdit" to activate' \
          -e 'tell application "TextEdit" to make new document' \
          -e 'tell application "TextEdit" to set bounds of front window to {80, 120, 780, 620}' \
          -e 'tell application "TextEdit" to make new document' \
          -e 'tell application "TextEdit" to set bounds of front window to {820, 120, 1420, 620}'
sleep 1
A="Untitled"; B="Untitled 2"
B_FRAME="$("$probe" TextEdit | awk -F'\t' -v t="$B" '$2 == t { print $3 }')"

echo "1. Parking"
launch_tatami 1
focus_doc "$B"
key 19 "control down, option down, shift down"   # send focused window to Stage 2
expect "$B" parked  "window sent to an inactive Stage is parked"
expect "$A" visible "window on the active Stage stays visible"

echo "2. Switching"
key 19 "control down, option down"               # switch to Stage 2
expect "$B" visible "target Stage window is shown"
expect "$A" parked  "previous Stage window is parked"

echo "3. Follow activated window"
focus_doc "$A"
expect "$A" visible "focusing a parked window switches to its Stage"
expect_frame "$A" "$(echo 80,120 700x500)" "unparked window returns to its exact frame"
expect "$B" parked  "the other Stage is parked after following"

echo "4. Graceful quit restores"
kill -TERM "$tatami_pid"; wait "$tatami_pid" 2>/dev/null || true; tatami_pid=""
sleep 1
expect "$A" visible "window restored on quit"
expect "$B" visible "parked window restored on quit"
expect_frame "$B" "$B_FRAME" "restored to its exact original frame"

echo "5. Crash recovery"
launch_tatami 1
focus_doc "$B"
key 19 "control down, option down, shift down"
expect "$B" parked "parked before crash"
kill -KILL "$tatami_pid"; wait "$tatami_pid" 2>/dev/null || true; tatami_pid=""
expect "$B" parked "still parked after crash (no cleanup ran)"
launch_tatami 0
expect "$B" visible "recovered on next launch from the journal"
expect_frame "$B" "$B_FRAME" "recovered to its exact original frame"

echo
if [ "$failures" -eq 0 ]; then echo "All checks passed."; else echo "$failures check(s) failed."; exit 1; fi
