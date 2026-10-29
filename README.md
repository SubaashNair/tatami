# Tatami

A native macOS workspace manager. Give each project a Stage, move windows between contexts, and arrange your desk with shortcuts.

## Build and run

Requires macOS 14+ and Xcode command-line tools with Swift 5.10 or later. No external dependencies.

```sh
swift test
bash scripts/package_app.sh
open dist/Tatami.app
```

If the project lives in `~/Documents` (or another iCloud/Finder-tagged folder), `swift test` may fail with "resource fork, Finder information, or similar detritus not allowed". Build outside it: `swift test --scratch-path /tmp/tatami-build`.

To sign with a stable identity (needed so Keychain-stored AI keys don't re-prompt after each rebuild), list identities with `security find-identity -v -p codesigning` and run `TATAMI_SIGN_IDENTITY="Apple Development: …" bash scripts/package_app.sh`.

The package can also be opened directly in Xcode with `Package.swift`. The packaging script builds a local, ad-hoc signed app. Distribution requires your own Developer ID signing and notarization.

1. Open Tatami and choose **Connect Tatami**.
2. Enable Tatami under System Settings → Privacy & Security → Accessibility. Turn off Apple's Stage Manager.
3. Create or rename Stages. Use a window's menu to move it or set an app-routing rule.
4. Choose **Start managing** when ready. Stage switching moves inactive windows just off screen (1 pt stays in a display corner), so switching is instant. If you use AeroSpace, yabai, or Amethyst, quit it first: two managers fight over the same windows.
5. Close the dashboard to continue using the menu-bar app. Quit restores every window Tatami hid.

## Implemented in 0.1

- Native SwiftUI/AppKit dashboard and menu-bar controls.
- Up to nine named Stages; create, rename, reorder, remove, switch, send windows, and undo.
- Accessibility permission onboarding and standard-window discovery.
- Instant Stage switching by parking windows off screen, with a per-window minimize fallback; recovery journal, pause/restore, and rescue.
- Event-driven window tracking on a dedicated Accessibility thread (no main-thread polling).
- Focusing a window from another Stage (Cmd+Tab, Dock) switches to it; returning to a Stage focuses its last-used window.
- Workspace continuity: Stage membership survives quits, crashes, and reboots. Launch at Login is on by default.
- Hardware display identity; windows from a disconnected display move to the one under the pointer, with a Restore / Keep Current prompt on reconnect.
- Sixteen snap zones, per-display grid arrangement, spacing preference, and geometry undo.
- Carbon global shortcuts with conflict reporting; Standard and Classic presets.
- Save, preview, rename, delete, and load arrangements of currently open windows.
- Ordered app and title routing rules; app-wide always-visible exclusions.
- Local JSON persistence, validated settings backup/import, and launch-at-login preference.
- AI Organizer with your own key (Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter, custom OpenAI-compatible) or a local model (Ollama, LM Studio). Describe a desk; review the proposed plan; apply it as one undoable step.

## TabStack

Press Control + Option + B to tile the focused display on the current Stage. Each window gets a pane (up to four; more windows become tabs), and each pane has a tab bar: click a tab to show it, right-click for Close, Split, Keep Floating, or Move to Stage, and use the ⋯ menu for Split, Zoom, Even Out, Reflow, Undo, or Close Pane. Background tabs are parked like inactive Stages, so Cmd+Tab to one simply selects it. Drag a tiled window's edge to resize; only its neighbours change. New windows get their own pane until a display has four, then join the focused pane as tabs (see Preferences). System Settings, Calculator, and similar utility windows float by default. Press Control + Option + B again to return every window to its Freeform position. Layout undo keeps 20 steps per display.

## Stages Bar

Rest the pointer at the top centre of any screen (or press the Stages Bar shortcut) to see every Stage as a card. Each card is a scaled map of all your displays with windows at their real positions and the apps on each display. Click a card to switch, click its name to rename it, hover to close it (Undo is available), or use + for a new Stage. Drag cards to reorder them. Drag any window by its title bar to the top edge and drop it on a card to send it there, or on + to give it a new Stage. Opened from the keyboard, use ←/→ and Return, or 1–9.

Tatami runs from the menu bar without a Dock icon (turn Show in Dock on in Preferences). Sort Windows into Stages… in the menu bar or dashboard groups chat apps, browsers, and everything else, as a preview you confirm.

## AI Organizer

Open it with Control + Option + Z while managing, from the menu bar (Arrange with AI…), or from the dashboard sidebar. Choose a provider and save its key under Preferences → AI Organizer; keys are stored in your Keychain.

The AI can create and rename Stages, move windows between Stages, and snap windows into zones on any display. It cannot delete Stages, change rules or preferences, or open and close apps. Every action is validated against your open windows before the preview is shown, and invalid actions are listed with a reason.

What is sent: app names, bundle IDs, window positions, Stage names, display sizes, and (unless turned off per provider) window titles. Before the first request to a cloud provider, Tatami shows the destination host and asks for confirmation. Requests go directly to the provider; redirects are refused so keys only reach the configured host. Local presets never leave this Mac. AI settings are not included in settings exports or imports.

## Controls

Global shortcuts register only while Stage management is running.

| Action | Standard shortcut | Classic shortcut |
|---|---|---|
| Switch Stage | Control + Option + 1–9 | Option + 1–9 |
| Send focused window | Control + Option + Shift + 1–9 | Option + Shift + 1–9 |
| Previous / next Stage | Control + Option + Command + Left / Right | Option + Left / Right |
| Cycle Stages | Control + Option + Tab (Shift reverses) | Option + Tab |
| Switch by scrolling | Control + Option + scroll | Option + scroll |
| Stages Bar | Control + Option + Command + Up | Option + Up |
| New / close Stage | Control + Option + N / X | Option + N / X |
| Merge all Stages | Control + Option + M | Option + M |
| Freeform ↔ TabStack (focused display) | Control + Option + B | Option + B |
| Focus pane up / left / down / right | Control + Option + Command + I / J / K / L | Command + Option + I / J / K / L |
| Move window to that pane | add Shift | add Shift |
| Previous / next tab | Control + Option + [ / ] | same |
| Split right / below | Control + Option + Command + \ / Shift + \ | Command + Option + \ / Shift + \ |
| Send window to previous / next display | Control + Option + Command + Shift + [ / ] | Command + Option + Shift + [ / ] |
| Grow / shrink pane | Control + Option + Command + = / − | Command + Option + = / − |
| Zoom pane, Reflow as Grid, Layout undo, Raise Floats | Control + Option + Command + Return / G / Z / F | Command + Option + Return / G / Z / F |
| Arrange active Stage | Control + Option + Command + Down | Option + Down |
| Snap halves | Control + Option + arrows | same |
| Snap quarters | Control + Option + U / I / J / K | same |
| Snap thirds | Control + Option + A / S / D | same |
| Snap two thirds | Control + Option + Q / R / W | same |
| Center / maximize | Control + Option + C / Return | same |
| Rescue and pause | Control + Option + Command + R | same |

Standard is the default because Option alone is macOS word navigation and character input. Classic is available in Preferences. Select a window row to use the dashboard's snap controls.

## Current limits

This is the first implementation milestone, not full PRD parity. TabStack drag-and-drop overlay and appearance settings, layout presets, Action Wheel, AI Recipes, managed AI, display pinning, licensing, arbitrary shortcut recording, automatic layout continuity, and full app/document reopening are not implemented. Stage previews are app-icon schematics, not captured thumbnails. The only network requests are AI Organizer requests you start, sent to the provider you chose.

Hidden windows are parked in a bottom corner of their own display with 1 pt visible. When both bottom corners border another display, or an app refuses to move off screen, that window is minimized instead. Windows you minimize yourself stay minimized. Dragging a parked window back or restoring a minimized one from the Dock moves it to the active Stage.

Real window frames are journaled before any window is hidden. Quit, `killall Tatami`, and the next launch after a crash all put windows back. If Accessibility is revoked while windows are parked, macOS stops Tatami from moving them until access is granted again, at which point they return automatically; meanwhile Window → Fill (macOS 15+) in an app's menu brings a window back.

Saved arrangements match running apps by bundle ID, window title, and occurrence. Renamed/closed windows are reported as unmatched. They do not reopen documents, preserve native tab trees, or provide reliable cross-reboot window identity. Display changes refresh geometry; automatic original-display return is not yet implemented. Some apps impose minimum window sizes or reject Accessibility operations.

Data is stored under `~/Library/Application Support/Tatami/`. Workspace files contain window titles and app identifiers; nothing is uploaded. Portable exports omit saved window arrangements. This version includes Stage definitions in settings exports (a documented deviation from the reference product).

See [the product requirements](docs/betterstage-inspired-prd.md) and [implementation status](docs/implementation-status.md).
