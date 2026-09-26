# M2: Stages polish

Status: decisions settled (design review 2026-09-26), ready to build. Part of [betterstage-parity.md](betterstage-parity.md). Covers PRD BAR-01 to BAR-06, STG-04, STG-07, STG-08, ONB-02, ONB-06, and the Stages rows of the parity table.

## Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Card previews | Schematic mini-desk: windows drawn to scale at their real frames with app icon and title. No Screen Recording. Real previews may come later as an opt-in. |
| 2 | Bar placement | Floating panel at the top-centre of the display under the pointer: one card per Stage plus a "+" card. |
| 3 | Hot zone | Global mouse-moved monitor. Opens when the pointer rests in the top-centre third of a display for the delay (default 0.2 s, 0–2 s). Option to ignore the notch area. Never intercepts clicks. |
| 4 | Shortcuts | Standard / Classic: Stages Bar ⌃⌥⌘↑ / ⌥↑ (dashboard moves to the menu bar); New Stage ⌃⌥N / ⌥N; Close Stage ⌃⌥X / ⌥X; Merge All ⌃⌥M / ⌥M; Cycle ⌃⌥Tab, ⌃⌥⇧Tab / ⌥Tab, ⌥⇧Tab. |
| 5 | Scroll switching | Standard ⌃⌥+scroll, Classic ⌥+scroll, on by default. One switch per gesture: accumulated delta threshold plus a short cooldown. Event tap swallows only matching scrolls. |
| 6 | Dock icon | Menu-bar-only by default, "Show in Dock" preference. |
| 7 | Sorting windows | Built-in categories (chat/mail → Comms, browsers → Browse, everything else → Work) shown as a preview to confirm or skip, plus "Ask AI" when a provider is configured. |
| 8 | Merge All | Every window moves to the first Stage; other Stages are removed. One-step Undo. |
| 9 | Switch indicator | Click-through pill with Stage number and name for about 1.5 s, near the top of the display under the pointer. On by default. |
| 10 | Multi-display cards | Each card draws all displays in their real arrangement, scaled. |
| 11 | Window drag to bar | In M2. Dragging a window by its title bar to the top edge opens the bar; dropping on a card sends it there (on "+" creates a Stage first). The window returns to its pre-drag frame, then parks with its Stage. |
| 12 | Bar keyboard | Opened by shortcut: keyboard focus, ←/→ select, Return switch, 1–9 jump, Esc close. Opened by hot zone: no key focus, closes about 2 s after the pointer leaves. |
| 13 | Closing a Stage | Card ×, ⌃⌥X, and the dashboard all close immediately and show "Stage closed. Undo". Windows move to the active Stage (first Stage if closing the active one). |
| 14 | Sorting availability | First run (no settings file) and "Sort Windows into Stages…" in the menu bar and dashboard. |
| 15 | Build order | Five commits (below). |

Also settled: Cmd+` limited to the active Stage is off by default; "follow when routed" comes from follow-on-focus; the status item keeps showing the Stage name.

## Build order

1. **Shortcuts and actions:** new, close, merge, Tab cycle, scroll switching. `TatamiCore`: merge, cycle order, sorting categories, with tests first.
2. **Switch indicator and menu-bar-only mode.**
3. **Stages Bar:** panel, schematic multi-display cards, click to switch, inline rename, × close, "+", keyboard navigation, hot zone with delay and notch settings.
4. **Drag and drop:** reorder cards, drag a window onto a card, drop on "+".
5. **Sorting and Cmd+`:** first-run and on-demand sorting preview, Cmd+` scoping, README and parity updates, review.

## Test plan

- [ ] Unit: merge result and undo snapshot, cycle wrap-around, category classification, scroll gesture accumulator.
- [ ] Integration (`scripts/ax_integration.sh`): new Stage, close Stage moves windows, merge, Tab cycling.
- [ ] Manual: hot zone delay and notch option, bar keyboard navigation, inline rename, window drag onto a card and onto "+", card reorder, scroll switching with mouse and trackpad, menu-bar-only mode, sorting preview.
