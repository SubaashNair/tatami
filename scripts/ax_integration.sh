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
tiles_ok() {  # every visible test window on screen, none overlapping another (TextEdit's own panels are ignored)
    "$probe" TextEdit | TEST_WINDOWS="$A	$B	$C" python3 -c '
import os, sys
ours = set(os.environ["TEST_WINDOWS"].split("\t"))
rects = []
for line in sys.stdin:
    state, title, frame = line.rstrip("\n").split("\t")
    if state != "visible" or title not in ours: continue
    pos, size = frame.split(" "); x, y = map(int, pos.split(",")); w, h = map(int, size.split("x"))
    rects.append((x, y, x + w, y + h))
bad = [(a, b) for i, a in enumerate(rects) for b in rects[i+1:] if min(a[2], b[2]) - max(a[0], b[0]) > 4 and min(a[3], b[3]) - max(a[1], b[1]) > 4]
print("ok" if len(rects) >= 3 and not bad else "bad %d %s" % (len(rects), bad))'
}
expect_tiles() { local r; r="$(tiles_ok)"; if [ "$r" = "ok" ]; then echo "  ok   $1"; else echo "  FAIL $1: $r"; failures=$((failures + 1)); fi; }
focus_doc() { osascript -e 'tell application "TextEdit" to activate' -e "tell application \"TextEdit\" to set index of window \"$1\" to 1"; sleep 1; }
launch_tatami() {
    TATAMI_DATA_DIR="$data" TATAMI_AUTOSTART="$1" TATAMI_ONLY_BUNDLES=com.apple.TextEdit dist/Tatami.app/Contents/MacOS/Tatami >/dev/null 2>&1 &
    tatami_pid=$!
    sleep 3
}

echo "Setting up TextEdit windows"
# TextEdit numbers new documents after any it remembers ("Untitled 12"), so the names are read back, not assumed.
names="$(osascript -e 'tell application "TextEdit"' -e 'activate' \
          -e 'make new document' -e 'set bounds of front window to {80, 120, 780, 620}' -e 'set a to name of front window' \
          -e 'make new document' -e 'set bounds of front window to {820, 120, 1420, 620}' -e 'set b to name of front window' \
          -e 'make new document' -e 'set bounds of front window to {300, 300, 900, 700}' -e 'set c to name of front window' \
          -e 'end tell' -e 'return a & tab & b & tab & c')"
IFS=$'\t' read -r A B C <<< "$names"
sleep 1

# These checks are about parking and exact frames, so the test desk starts in Freeform (Tiles is the shipped default
# and has its own checks in step 11). Three Rooms, like a first run.
w="$(uuidgen)"; s="$(uuidgen)"; b="$(uuidgen)"
cat > "$data/workspace.json" <<JSON
{"version": 1, "activeStageID": "$w", "tilesByDefault": false,
 "stages": [{"id": "$w", "name": "Work", "symbol": "square.grid.2x2"},
            {"id": "$s", "name": "Comms", "symbol": "bubble.left.and.bubble.right"},
            {"id": "$b", "name": "Browse", "symbol": "globe"}]}
JSON
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
expect "$B" parked "checkpoint put the window back on Stage 2 at launch, parked"
kill -KILL "$tatami_pid"; wait "$tatami_pid" 2>/dev/null || true; tatami_pid=""
expect "$B" parked "still parked after crash (no cleanup ran)"
launch_tatami 0
expect "$B" visible "recovered on next launch from the journal"
expect_frame "$B" "$B_FRAME" "recovered to its exact original frame"

echo "6. Checkpoint restores Stage membership"
kill -TERM "$tatami_pid"; wait "$tatami_pid" 2>/dev/null || true; tatami_pid=""
launch_tatami 1
expect "$B" parked  "after restart, the window is back on Stage 2 and parked"
expect "$A" visible "Stage 1 window stays visible"

echo "7. Cycle Stages with Tab"
key 48 "control down, option down"                # next Stage
expect "$B" visible "Control+Option+Tab shows the next Stage"
expect "$A" parked  "and parks the previous one"
key 48 "control down, option down, shift down"    # previous Stage
expect "$A" visible "Control+Option+Shift+Tab goes back"

echo "8. Scroll to switch"
"$probe" scroll -3; sleep 1
expect "$B" visible "Control+Option+scroll down switches to the next Stage"
"$probe" scroll 3; sleep 1
expect "$A" visible "scroll up switches back"
expect "$B" parked  "and parks the other Stage"

echo "9. Merge All"
key 46 "control down, option down"                # M
expect "$A" visible "merge shows every window"
expect "$B" visible "including the one from Stage 2"

echo "10. New and Close Stage"
key 45 "control down, option down"                # N: new Stage, switched to
expect "$A" parked "a new empty Stage parks the others"
key 7 "control down, option down"                 # X: close current Stage
expect "$A" visible "closing it returns to a Stage with the windows"
expect "$B" visible "all windows are back"

echo "11. TabStack"
focus_doc "$A"
key 11 "control down, option down"                # B: TabStack on this display
expect_tiles "three windows tile side by side with no overlap"
focus_doc "$A"
key 37 "control down, option down, command down, shift down"   # move A into the pane to its right
expect "$B" parked  "the window it joined becomes a background tab and is parked"
expect "$A" visible "the moved window is the selected tab"
key 30 "control down, option down"                             # ] next tab
expect "$B" visible "Control+Option+] shows the other tab"
expect "$A" parked  "and parks the one that was showing"
key 6 "control down, option down, command down"                # Z: layout undo
expect_tiles "layout undo restores three separate panes"
key 11 "control down, option down"                # back to Freeform
expect_frame "$A" "80,120 700x500" "Freeform restores the exact pre-TabStack frame"

echo
if [ "$failures" -eq 0 ]; then echo "All checks passed."; else echo "$failures check(s) failed."; exit 1; fi
