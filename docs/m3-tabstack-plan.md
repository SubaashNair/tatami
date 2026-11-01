# M3: TabStack core

Status: decisions settled (design review 2026-09-27), ready to build. Part of the internal feature roadmap (not published). Covers PRD TIL-01 to TIL-04, TIL-06, TIL-07, TIL-12 to TIL-15 and the M3 rows of the parity table. Drag overlay, appearance, presets, native-tab apps, Launch Here, and divider handles are M4.

## Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Tabs | Tatami draws a 28 pt tab bar panel above each pane; the selected window sits below it. The bar carries the pane "⋯" menu. |
| 2 | Background tabs | Parked off-screen with M1's journal and recovery. Cmd+Tab to a background tab selects it. |
| 3 | Model | n-ary tree: containers are rows or columns with child weights; normalized (no single-child containers, alternating orientation). |
| 4 | Entering TabStack | Per display, per Stage; Freeform stays the default. Existing windows get a balanced grid, one pane each up to 4; extras join the largest pane as tabs. Leaving restores pre-TabStack Freeform frames. |
| 5 | Shortcuts | Standard / Classic: focus pane ⌃⌥⌘ IJKL / ⌘⌥ IJKL; move window ⌃⌥⌘⇧ IJKL / ⌘⌥⇧ IJKL; tabs ⌃⌥ [ ] (both); cycle mode ⌃⌥B / ⌥B; Even Out ⌃⌥⌘↓ / ⌥↓ (Arrange in Freeform); Reflow ⌃⌥⌘G / ⌘⌥G; Zoom ⌃⌥⌘Return / ⌘⌥Return; split right / below ⌃⌥⌘\ ⌃⌥⌘- / ⌘⌥\ ⌘⌥-. |
| 6 | Layout undo | 20 steps per display per Stage, layout mutations only, ⌃⌥⌘Z. |
| 7 | Minimum sizes | Window stays in its pane at its minimum size, anchored top-left, with a ⚠︎ on its tab. |
| 8 | Floating | Default float list (System Settings, Calculator, Activity Monitor utility windows, Preview inspectors, Finder Get Info, picture-in-picture); per-window Automatic / Manage in Layout / Keep Floating, savable as an app rule. |
| 9 | New windows | Automatic: own pane by splitting the focused pane along its longer side while the display has fewer than 4 panes, else a tab in the focused pane. Active / Adjacent / Own pane selectable. Routing and Launch Here take precedence. |
| 10 | Empty panes | Removed by default, siblings grow; "Keep empty panes" setting. |
| 11 | Persistence | Mode per Stage per display in settings; pane trees and membership in the checkpoint, matched by window number. |
| 12 | Display disconnect | Windows join the focused pane on the remaining display as tabs; the lost layout is remembered and rebuilt by M1's Restore prompt. |
| 13 | Snap keys in TabStack | Floating windows snap as usual; for managed windows the arrow snaps move to the neighbouring pane, others do nothing. |
| 14 | Resizing | Dragging a managed window's edge adjusts only the adjacent panes' weights; ⌃⌥⌘= / ⌃⌥⌘− grow and shrink the focused pane. Handles and ghost preview in M4. |
| 15 | Floats visibility | Raise Floats ⌃⌥⌘F / ⌘⌥F, plus automatic raise after Tatami's own layout changes. |
| 16 | Build order | Five commits (below). |

Also settled: only standard windows are tiled; tab context menu has Close, Close Others, Close Tabs to the Right, Keep Floating, Split Right/Below, Move to Stage; closing a tab presses the window's own close button; MRU tab selection (TIL-03); focus and move cross displays at the edge (TIL-06); zoom survives tab switches in the same pane (TIL-07); tab bars hide with their Stage; the AI choosing Window Modes is M8.

## Build order

1. **Layout engine in TatamiCore, tests first:** tree, normalization, split, join, swap, move, remove, insert, directional neighbours across displays, frame computation with gaps and tab bars, weight changes from an edge drag, Even Out, Reflow as Grid, undo history, new-window placement.
2. **Mode switching:** per-Stage per-display mode, balanced entry layout, Freeform restore, ⌃⌥B, checkpoint persistence.
3. **Applying layouts:** pane placement, background-tab parking, minimum sizes, edge-drag resize, floating defaults, per-window behaviour and rules, Raise Floats.
4. **Tab bar panel:** tabs, MRU selection, context and pane menus, ⚠︎ badge.
5. **Keyboard and remaining actions:** focus, move, tabs, zoom, split, resize, Even Out, Reflow, undo; TabStack snap-key behaviour; disconnect handling; docs; review.

## Test plan

- [ ] Unit: normalization invariants, every mutation, neighbours across displays, frames with gaps/tab bars/min sizes, edge-drag weights, Even Out, Reflow, undo depth, placement rules.
- [ ] Integration: three TextEdit windows in TabStack: non-overlapping tiles, background tab parked, focus and move between panes, Even Out, undo, back to Freeform restores frames.
- [ ] Manual: tab bar clicks and menus, edge-drag resize, floating defaults, Raise Floats, min-size apps, Cmd+Tab to a background tab, display disconnect with TabStack.
