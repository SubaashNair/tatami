# Per-display Rooms

An opt-in mode where each display shows its own Room and switches on its own. Off by default, where one Room is active on every display.

## Rules

- A window is visible when its Room is the one showing on the display it sits on. Windows of other Rooms on that display are hidden. Always-visible apps are never hidden.
- Switching the Room on one display never moves another display. A switch pins every other connected display to the Room it shows now.
- A display with no entry of its own (new, or never switched) follows the last switched Room.
- A window sent to a display joins the Room showing there, so it never disappears on arrival.
- A removed Room never stays active: displays that pointed at it fall back to the last switched Room. Merge All puts every display on the surviving Room.
- Turning the mode off puts every display on the last switched Room.

## Phases

1. **Core model** (done): the rules above in `TatamiCore` with unit tests.
2. **Wiring** (this change): hiding and showing windows per display, switching, focus following, new windows, Tiles and sending windows. Turn it on in Preferences, under Displays (experimental). Off by default, and with it off nothing behaves differently.
3. **Interface:** keys, per-display Room cards, the dashboard switch, the `tatami room --display` option, docs.

Each phase needs testing on a real multi-display setup before the next starts, because it decides which windows get hidden.

## Testing phase 2 by hand (two or more displays)

1. Preferences, Displays: turn on "Each display shows its own Room".
2. With the pointer or a focused window on display 1, press the Room 2 key. Only display 1 should change; display 2 keeps its windows.
3. Switch display 2 to another Room. Cycling Rooms, Cmd+Tab to a hidden app and Dock clicks should act on the display the window is on.
4. Drag a window to the other display: it should join the Room showing there and stay visible.
5. Send a window with the display key: same result.
6. Turn the setting off: every display returns to one Room and every window is reachable. `⌃⌥⌘R` (rescue) always brings everything back.

## Room homes (planned build order)

A Room can live on a display, so "coding apps on display 1, chat on display 2, teaching on display 3" is a setting. Apps are routed to a Room with App Routing; the Room's home decides the display.

- Setting a home turns per-display Rooms on and makes that display show the Room.
- A Room with a home opens its new windows as tabs in the focused pane (a Room can pick another layout).
- A routed window is moved to its Room's home. If that display is showing another Room the window waits there, hidden, until you switch the display to the Room, like any inactive Room.
- An unplugged home display is ignored. With the mode off homes are ignored. Merge All drops the home of the surviving Room.

Steps: 1. core rules (done), 2. wiring (done), 3. the Room settings screen (a Room's ⋯ menu, Room Settings…) and the AeroSpace import (App Routing, Import from AeroSpace…).

### Trying step 2

There is no settings screen yet, so set a home from a terminal:

```bash
tatami list rooms        # numbers and names
tatami list displays     # numbers and names
tatami home 1 1          # Room 1 lives on display 1 (its windows open there, as tabs)
tatami home 2 2          # Room 2 lives on display 2
tatami home 2 none       # clear it
```

Then route apps with App Routing (dashboard) to those Rooms. A window that opens **after** management started, from a routed app, is moved to its Room's display and joins the focused pane as a tab. Windows already open are not moved, and a window you move yourself stays where you put it.
