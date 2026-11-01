# M1: Engine foundations

Status: implemented 2026-09-26. Decisions settled in design review 2026-09-24. Part of the internal feature roadmap (not published). Covers PRD STG-03, STG-06, DSP-02, DSP-03, DSP-06, DSP-07, WSP-01 to WSP-05, SET-01, SET-10 (as far as macOS allows).

## Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Hiding | Park inactive windows off-screen. Per-window fallback to minimize when a window refuses to move off-screen. No separate "safe mode". |
| 2 | Threading | One dedicated AX thread with its own run loop owns every AX call and observer; publishes snapshots to the main actor. |
| 3 | Safety net | AX observer events, plus a 5 s background rescan, plus rescans on app launch/quit, wake, display change, Stage switch. |
| 4 | Display identity | Vendor + model + serial; ties (serial 0, identical monitors) broken by arrangement order (left to right, top to bottom); CG display UUID as last fallback. |
| 5 | Window identity | `_AXUIElementGetWindow` window number within a session; after app relaunch, app + title + occurrence. Public-API fallback if the symbol is missing. |
| 6 | AXEnhancedUserInterface | Disable per app only around each move, then restore the previous value. |
| 7 | Performance | Log every switch with `os_signpost`. Targets: visible switch under 50 ms for 20 windows, under 1% idle CPU, under 80 MB. Moves run in parallel per app. |
| 8 | Reconnect | Non-blocking Restore / Keep Current Layout panel on the display under the pointer, in M1. |
| 9 | Park location | Corner of the window's own display with 1 pt visible; pick a corner with no neighbouring display beyond it; minimize if no corner is free. |
| 10 | Crash safety | Journal real frames before parking; restore on next launch; Launch at Login defaults on. No watchdog helper. |
| 11 | Focus on parked window | Follow activated windows: focusing a window from another Stage switches to that Stage. Preference toggle, default on. |
| 12 | Switch order | Unpark target Stage, then park the rest, then focus the Stage's last-focused window. |
| 13 | Checkpoints | Window number, app, title, real frame, Stage, display fingerprint, active Stage, last-focused per Stage. Debounced 1 s after changes, immediate on quit/sleep/display change. Match by window number, then app + title + occurrence. |
| 14 | Disconnect | Map windows proportionally onto the display under the pointer; remember originals for Restore. |
| 15 | Build order | Six commits (below). |
| 16 | Testing | Unit tests for all pure logic, an opt-in TextEdit integration script, and a manual app checklist. |

Also settled: Rescue un-parks everything to journaled frames; undo snapshots and saved workspaces store real frames only; switch timings go to `os.Logger`; a new window that appears inside a park zone (an app that saved its parked frame) is moved on-screen; the 0.1 minimize journal is still honoured on first launch.

## Build order

1. **TatamiCore logic, tests first:** `DisplayFingerprint` matching, `ParkPlanner` corner choice, `DisplayRemap` proportional mapping, `CheckpointMatcher` window reconciliation, park-zone detection.
2. **Event pipeline:** `AXThread`, per-app `AXObserver`s (window created/destroyed/moved/resized/focused, app activated), window-number identity, 5 s rescan. Removes the main-thread polling freeze.
3. **Parking:** journal, show-then-park switching, last-focused per Stage, follow-on-focus, minimize fallback, 0.1 journal migration, park-zone rescue for relaunched apps.
4. **Checkpoints:** debounced writer, restore on launch, Launch at Login default on.
5. **Displays:** disconnect remap, reconnect Restore / Keep Current panel.
6. **Polish:** AXEnhancedUserInterface toggling, signpost timing, README and PRD status updates.

## Test plan

- [x] Unit: fingerprint matching (serial 0, identical twins, port swap, resolution change), corner choice (single display, side-by-side, stacked, 3×3), proportional remap, checkpoint matching (window number, title change, duplicate titles, app relaunch), park-zone detection.
- [ ] Integration (`scripts/ax_integration.sh`, opt-in, needs Accessibility for the terminal): TextEdit windows on two Stages; switch; assert parked/visible frames; quit Tatami; assert restored.
- [ ] Manual on Safari, Chrome, Finder, Terminal, Xcode, VS Code, Slack, Preview: switch, Cmd+Tab follow, Rescue, force-quit then relaunch recovery, unplug/replug display, sleep/wake.
