# Tatami

A native macOS workspace manager. Give each project a Stage, move windows between contexts, and arrange your desk with shortcuts.

## Build and run

Requires macOS 14+ and Xcode command-line tools with Swift 5.10 or later. No external dependencies.

```sh
swift test
bash scripts/package_app.sh
open dist/Tatami.app
```

The package can also be opened directly in Xcode with `Package.swift`. The packaging script builds a local, ad-hoc signed app. Distribution requires your own Developer ID signing and notarization.

1. Open Tatami and choose **Connect Tatami**.
2. Enable Tatami under System Settings → Privacy & Security → Accessibility. Turn off Apple's Stage Manager.
3. Create or rename Stages. Use a window's menu to move it or set an app-routing rule.
4. Choose **Start managing** when ready. Stage switching minimizes inactive windows, leaving them accessible through the macOS Dock.
5. Close the dashboard to continue using the menu-bar app. Quit restores windows minimized by Tatami.

## Implemented in 0.1

- Native SwiftUI/AppKit dashboard and menu-bar controls.
- Up to nine named Stages; create, rename, reorder, remove, switch, send windows, and undo.
- Accessibility permission onboarding and standard-window discovery.
- Per-window minimization for Stage visibility, recovery journal, pause/restore, and rescue.
- Sixteen snap zones, per-display grid arrangement, spacing preference, and geometry undo.
- Carbon global shortcuts with conflict reporting; Standard and European presets.
- Save, preview, rename, delete, and load arrangements of currently open windows.
- Ordered app and title routing rules; app-wide always-visible exclusions.
- Local JSON persistence, validated settings backup/import, and launch-at-login preference.

## Controls

Global shortcuts register only while Stage management is running.

| Action | Standard shortcut |
|---|---|
| Switch Stage | Option + 1–9 |
| Send focused window | Option + Shift + 1–9 |
| Previous / next Stage | Option + Left / Right |
| Show dashboard | Option + Up |
| Arrange active Stage | Option + Down |
| Snap halves | Control + Option + arrows |
| Snap quarters | Control + Option + U / I / J / K |
| Snap thirds | Control + Option + A / S / D |
| Snap two thirds | Control + Option + Q / R / W |
| Center / maximize | Control + Option + C / Return |
| Rescue and pause | Control + Option + Command + R |

The European preset adds Control to Stage switching and sending. Select a window row to use the dashboard's snap controls.

## Current limits

This is the first implementation milestone, not full PRD parity. Tabbed Tiling, Action Wheel, AI Organizer, display pinning, licensing, arbitrary shortcut recording, automatic layout continuity, and full app/document reopening are not implemented. Stage previews are app-icon schematics, not captured thumbnails. No network requests are made.

Window management uses native minimization rather than off-screen parking. Windows minimized by the user are left minimized during normal Stage switching. Restoring one through the Dock moves it to the active Stage. If Accessibility is revoked, macOS prevents Tatami from restoring windows; they remain recoverable from the Dock. After an abnormal exit, Tatami attempts recovery when it next has Accessibility access.

Saved arrangements match running apps by bundle ID, window title, and occurrence. Renamed/closed windows are reported as unmatched. They do not reopen documents, preserve native tab trees, or provide reliable cross-reboot window identity. Display changes refresh geometry; automatic original-display return is not yet implemented. Some apps impose minimum window sizes or reject Accessibility operations.

Data is stored under `~/Library/Application Support/Tatami/`. Workspace files contain window titles and app identifiers; nothing is uploaded. Portable exports omit saved window arrangements. This version includes Stage definitions in settings exports (a documented deviation from the reference product).

See [the product requirements](docs/betterstage-inspired-prd.md) and [implementation status](docs/implementation-status.md).
