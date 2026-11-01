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

1. **Core model** (this change): the rules above in `TatamiCore` with unit tests. Nothing visible yet.
2. **Wiring:** hiding and showing windows per display, focus following, the recovery journal and checkpoints.
3. **Interface:** keys, per-display Room cards, the dashboard switch, the `tatami room --display` option, docs.

Each phase needs testing on a real multi-display setup before the next starts, because it decides which windows get hidden.

## Room homes (planned build order)

A Room can live on a display, so "coding apps on display 1, chat on display 2, teaching on display 3" is a setting. Apps are routed to a Room with App Routing; the Room's home decides the display.

- Setting a home turns per-display Rooms on and makes that display show the Room.
- A Room with a home opens its new windows as tabs in the focused pane (a Room can pick another layout).
- A routed window is moved to its Room's home. If that display is showing another Room the window waits there, hidden, until you switch the display to the Room, like any inactive Room.
- An unplugged home display is ignored. With the mode off homes are ignored. Merge All drops the home of the surviving Room.

Steps: 1. core rules (`RoomHomes.swift`, done), 2. moving windows home and keeping each display on its home Room, 3. the Room settings screen and the AeroSpace import.
