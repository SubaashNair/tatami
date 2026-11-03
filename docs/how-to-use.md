# How to use Tatami for productivity

Tatami groups your windows into **Rooms** (one per task or project). Switching a Room hides everything else and shows only that task's windows, instantly, across all your monitors.

Shortcuts below are the **Standard** preset (Control + Option based). Written as `⌃⌥` = Control + Option, `⌘` = Command, `⇧` = Shift.

## 1. Set up (5 minutes)

1. Build and open the app:
   ```sh
   swift test --scratch-path /tmp/tatami-build
   bash scripts/package_app.sh
   open dist/Tatami.app
   ```
2. Turn **Stage Manager off** (System Settings → Desktop & Dock). Quit AeroSpace, yabai, or Amethyst if running.
3. In Tatami choose **Connect Tatami**, then enable it under System Settings → Privacy & Security → Accessibility.
4. Create 3 Rooms, for example **Work**, **Comms**, **Browse**. Or use **Sort Windows into Rooms…** in the menu bar to group chat, browsers, and everything else automatically (you confirm a preview first).
5. Click **Start managing**. Shortcuts only work while managing is running.

Safety: `⌃⌥⌘R` (Rescue and pause) brings every hidden window back. Quitting Tatami also restores them.

## 2. The daily loop

| You want to | Do this |
|---|---|
| Jump to a task | `⌃⌥1` to `⌃⌥9` |
| Send the current window to another task | `⌃⌥⇧1` to `⌃⌥⇧9` |
| Go to previous / next Room | `⌃⌥⌘←` / `⌃⌥⌘→` |
| See all Rooms at once | `⌃⌥⌘↑`, or rest the pointer at the top centre of a screen |
| Make a new / close a Room | `⌃⌥N` / `⌃⌥X` (close shows Undo) |
| Collapse everything into one Room | `⌃⌥M` |

Room cards (rest the pointer at the top centre of a screen): click a card to switch, click a name to rename, drag a window by its title bar up to the cards and drop it on one (or on **+** for a new Room).

Tip: focusing a window from another Room (Cmd + Tab, Dock click) switches to that Room automatically.

### Moving between windows with the keyboard

Tatami is keyboard first: everything below works without the mouse, in freeform and in Tiles.

| You want | Keys |
|---|---|
| Focus the window above / left / below / right | `⌃⌥⌘` + I / J / K / L |
| Swap places with the freeform window that way (or move to the next pane in Tiles) | `⌃⌥⌘⇧` + I / J / K / L |
| Focus the previous / next window, across all displays | `⌃⌥⌘[` / `⌃⌥⌘]` |

Focus stops at the edge of your screens. Windows are ordered left to right across displays, then top to bottom. Classic uses `⌘⌥` in place of `⌃⌥⌘`.

**Going straight to a pane, and turning a split.** Each tab bar shows its pane's number (1, 2, 3…, in reading order across displays).

| You want | Keys |
|---|---|
| Focus pane 1 to 9 | `⌃⌥⌘1` to `⌃⌥⌘9` |
| Move the focused window into pane 1 to 9 | `⌃⌥⌘⇧1` to `⌃⌥⌘⇧9` |
| Turn the focused pane's split the other way (side by side to stacked, and back) | `⌃⌥⌘/` |

**Floating a window, and bringing it back.** `⌃⌥⌘T` floats the focused window (it sits in the middle of its display at half its tiled size) and, pressed on a floating window, puts it back into a pane. `⌃⌥⌘⇧T` does the same for every window of that app and remembers it; pressing it again removes the rule. A floating window has no tab bar, so the menu-bar item **Float or Tile Focused Window** is the mouse route. Focus and cycling keys reach floating windows too.

Rotate keeps every window and every pane size; it only changes the direction. If the pane's neighbours form a nested split, rotating can merge them into one row or column, and rotating again does not split them back (`⌃⌥⌘Z` does). Numbers read row by row, so a left pane with two stacked panes on its right is numbered 1, 2, 3 from the top row down.

## 3. Three productivity setups

**Deep work.** Put your editor, terminal, and docs in one Room. Put Slack and Mail in another. Work in Room 1 with notifications out of sight, and check Room 2 on your own schedule with `⌃⌥2`.

**Several projects.** One Room per project, named after it. Open the project's files and browser windows there. `⌃⌥1` to `⌃⌥9` becomes your project switcher, and each Room remembers its last focused window.

**Two monitors.** Rooms span all displays. Keep your main app on one display and reference material on the other, per Room. Switching one Room swaps both screens at once.

Set a routing rule (a window's menu, then app routing) so Slack always lands in Comms. Mark always-visible apps (for example Music) as exclusions so they never hide.

## 4. Arranging windows inside a Room

**Snap** (freeform windows):

| Shape | Shortcut |
|---|---|
| Halves | `⌃⌥` + arrow keys |
| Quarters | `⌃⌥` + U / I / J / K |
| Thirds | `⌃⌥` + A / S / D |
| Two thirds | `⌃⌥` + Q / R / W |
| Center / maximize | `⌃⌥C` / `⌃⌥Return` |

**Tiles** (tiling with tab bars), per display per Room:

0. Tiles is the default. While Tatami is managing, every window you open joins a pane by itself, with no key press. `⌃⌥B` switches the focused display to Freeform and back. Preferences has **Tile new windows automatically** to change the default.
1. Each window gets a pane (up to four); extras become tabs.
2. Move around: focus a pane with `⌃⌥⌘` + I / J / K / L, move the window there by adding `⇧`.
3. Switch tabs with `⌃⌥[` and `⌃⌥]`. Click a tab to select it, right-click for Close, Split, Keep Floating, Move to Room.
4. Resize: drag a window edge, or use `⌃⌥⌘=` and `⌃⌥⌘−`.
5. Zoom a pane `⌃⌥⌘Return`, reflow as grid `⌃⌥⌘G`, undo layout `⌃⌥⌘Z`.
6. Press `⌃⌥B` again to put every window back where it was.

**Two displays:** to send a window to the other screen, right-click its tab and choose **Move to Display**, or press `⌃⌥⌘⇧[` (previous display) or `⌃⌥⌘⇧]` (next display). On a tiled display it joins the focused pane as a tab. On a freeform display it keeps its relative position and size.

Not available yet: drag-to-split, drag a tab to another pane or display, divider handles, layout presets.

### Give each display its own Room (experimental)

Say display 1 is for coding, display 2 for chat and display 3 for teaching:

1. Create a Room for each job and route the apps to it in **App Routing**.
2. In the dashboard, open a Room's **⋯** menu, choose **Room Settings…**, and pick **Lives on** a display. This turns on "Each display shows its own Room".
3. Add more choices under **If that display is not connected, try**, such as another monitor or the built-in display. The first one that is connected wins, so the same setup works at home, at work and on the laptop alone.
4. Leave **New windows open as** on the default (tabs in the focused pane) so a second coding app joins the first one's pane.

Apps you open from then on go to their Room's display, as tabs. Windows already open stay where they are. From a terminal: `tatami home 1 1` puts Room 1 on display 1 (see the command-line guide).

**Coming from AeroSpace?** In **App Routing**, choose **Import from AeroSpace…** and pick your `~/.aerospace.toml`. Each `[[on-window-detected]]` workspace becomes a Room (you name them in the preview), each app its rules send there gets a routing rule (app names are matched against your installed apps, ignoring case), and `layout floating` becomes a float rule. Your `workspace-to-monitor-force-assignment` lists (monitor names, `main`, `secondary`, `built-in` or a position, first connected wins) become each Room's ordered home choices. Rules that match window titles or other conditions are listed as skipped. The import has undo, and an app that already has a routing rule keeps it.

### Wake from sleep and moving between desks

Tatami saves your layout (Rooms, tabs, panes and window positions) for each **set of connected displays**, as you work and just before sleep. When the Mac wakes, or you plug into a setup it has seen before, it waits a few seconds for the displays to settle and then puts the windows back by itself. Home (laptop, portable, room monitor) and work (laptop, portable, office monitor) are separate setups even though they share the portable monitor.

- A combination of displays it has never seen is left alone and starts being remembered.
- The restore has undo (`⌃⌥⌘Z` in the dashboard, or Undo there).
- Two monitors of the same model can look identical to the system and may be confused with each other.
- Setups are kept for 120 days, up to eight, in `setups.json` in Tatami's data folder.

## 5. Let AI sort a messy desktop

1. Preferences → AI Organizer: pick a provider and save your key (stored in Keychain). Ollama or LM Studio work locally with no key.
2. Press `⌃⌥Z`, describe what you want ("work stuff on the left, chat on the side screen"), review the preview, then Apply. One Undo reverts it.

## 6. Test checklist (15 minutes)

Do these in order and note anything odd. Use throwaway windows, not unsaved documents.

- [ ] Start managing with 3 Rooms and 6 or more windows (include Safari or Chrome, Finder, Terminal).
- [ ] Switch Rooms with `⌃⌥1` to `⌃⌥3` repeatedly. Check it feels instant and the right windows show.
- [ ] Cmd + Tab to a window in another Room. It should switch Room.
- [ ] Show the Room cards. Rename a Room, drag a window onto a card.
- [ ] Close a Room and click Undo.
- [ ] Snap a window to a half and a quarter, then undo the arrangement.
- [ ] Open a new app: it should join a pane by itself. Move focus with `⌃⌥⌘` + I / J / K / L, switch tabs, then press `⌃⌥B` to go to Freeform and back.
- [ ] Press `⌃⌥⌘R`. Everything should reappear. Start managing again.
- [ ] Quit Tatami with windows hidden. All windows should come back.
- [ ] With two displays: unplug one and check the Restore / Keep Current prompt on reconnect.
- [ ] Sleep and wake the Mac, then check Rooms still hold.

## 7. If something goes wrong

| Symptom | Try |
|---|---|
| A window is missing | `⌃⌥⌘R`, or quit Tatami |
| Shortcut does nothing | Is managing started? Does another app use that combo? Try the Classic preset in Preferences |
| Windows jump or fight | Another window manager or Stage Manager is still running |
| A window peeks out at a corner | Parked windows keep 1 pt visible. This is expected |
| An app window won't move off screen | Tatami minimizes it instead. This is expected |
| An app is too big for its pane (Photo Booth, apps with a minimum size) | Tatami first widens or heightens that pane at its neighbours' expense. If there is no room it floats the window and says so; `⌃⌥⌘T` tiles it again, `⌃⌥⌘Z` undoes a widened pane |
| Accessibility was revoked | Re-enable it; parked windows return on their own |

Data lives in `~/Library/Application Support/Tatami/`. For anything that breaks, note the app, what you pressed, and what happened.
