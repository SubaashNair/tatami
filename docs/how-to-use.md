# How to use Tatami for productivity

Tatami groups your windows into **Stages** (one per task or project). Switching a Stage hides everything else and shows only that task's windows, instantly, across all your monitors.

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
4. Create 3 Stages, for example **Work**, **Comms**, **Browse**. Or use **Sort Windows into Stages…** in the menu bar to group chat, browsers, and everything else automatically (you confirm a preview first).
5. Click **Start managing**. Shortcuts only work while managing is running.

Safety: `⌃⌥⌘R` (Rescue and pause) brings every hidden window back. Quitting Tatami also restores them.

## 2. The daily loop

| You want to | Do this |
|---|---|
| Jump to a task | `⌃⌥1` to `⌃⌥9` |
| Send the current window to another task | `⌃⌥⇧1` to `⌃⌥⇧9` |
| Go to previous / next Stage | `⌃⌥⌘←` / `⌃⌥⌘→` |
| See all Stages at once | `⌃⌥⌘↑`, or rest the pointer at the top centre of a screen |
| Make a new / close a Stage | `⌃⌥N` / `⌃⌥X` (close shows Undo) |
| Collapse everything into one Stage | `⌃⌥M` |

In the Stages Bar: click a card to switch, click a name to rename, drag a window by its title bar up to the bar and drop it on a card (or on **+** for a new Stage).

Tip: focusing a window from another Stage (Cmd + Tab, Dock click) switches to that Stage automatically.

## 3. Three productivity setups

**Deep work.** Put your editor, terminal, and docs in one Stage. Put Slack and Mail in another. Work in Stage 1 with notifications out of sight, and check Stage 2 on your own schedule with `⌃⌥2`.

**Several projects.** One Stage per project, named after it. Open the project's files and browser windows there. `⌃⌥1` to `⌃⌥9` becomes your project switcher, and each Stage remembers its last focused window.

**Two monitors.** Stages span all displays. Keep your main app on one display and reference material on the other, per Stage. Switching one Stage swaps both screens at once.

Set a routing rule (a window's menu, then app routing) so Slack always lands in Comms. Mark always-visible apps (for example Music) as exclusions so they never hide.

## 4. Arranging windows inside a Stage

**Snap** (freeform windows):

| Shape | Shortcut |
|---|---|
| Halves | `⌃⌥` + arrow keys |
| Quarters | `⌃⌥` + U / I / J / K |
| Thirds | `⌃⌥` + A / S / D |
| Two thirds | `⌃⌥` + Q / R / W |
| Center / maximize | `⌃⌥C` / `⌃⌥Return` |

**TabStack** (tiling with tab bars), per display per Stage:

1. Press `⌃⌥B` to tile the focused display. Each window gets a pane (up to four); extras become tabs.
2. Move around: focus a pane with `⌃⌥⌘` + I / J / K / L, move the window there by adding `⇧`.
3. Switch tabs with `⌃⌥[` and `⌃⌥]`. Click a tab to select it, right-click for Close, Split, Keep Floating, Move to Stage.
4. Resize: drag a window edge, or use `⌃⌥⌘=` and `⌃⌥⌘−`.
5. Zoom a pane `⌃⌥⌘Return`, reflow as grid `⌃⌥⌘G`, undo layout `⌃⌥⌘Z`.
6. Press `⌃⌥B` again to put every window back where it was.

**Two displays:** to send a window to the other screen, right-click its tab and choose **Move to Display**, or press `⌃⌥⌘⇧[` (previous display) or `⌃⌥⌘⇧]` (next display). On a tiled display it joins the focused pane as a tab. On a freeform display it keeps its relative position and size.

Not available yet: drag-to-split, drag a tab to another pane or display, divider handles, layout presets.

## 5. Let AI sort a messy desktop

1. Preferences → AI Organizer: pick a provider and save your key (stored in Keychain). Ollama or LM Studio work locally with no key.
2. Press `⌃⌥Z`, describe what you want ("work stuff on the left, chat on the side screen"), review the preview, then Apply. One Undo reverts it.

## 6. Test checklist (15 minutes)

Do these in order and note anything odd. Use throwaway windows, not unsaved documents.

- [ ] Start managing with 3 Stages and 6 or more windows (include Safari or Chrome, Finder, Terminal).
- [ ] Switch Stages with `⌃⌥1` to `⌃⌥3` repeatedly. Check it feels instant and the right windows show.
- [ ] Cmd + Tab to a window in another Stage. It should switch Stage.
- [ ] Open the Stages Bar. Rename a Stage, drag a window onto a card.
- [ ] Close a Stage and click Undo.
- [ ] Snap a window to a half and a quarter, then undo the arrangement.
- [ ] Press `⌃⌥B` for TabStack, move focus with `⌃⌥⌘` + I / J / K / L, switch tabs, then `⌃⌥B` to return.
- [ ] Press `⌃⌥⌘R`. Everything should reappear. Start managing again.
- [ ] Quit Tatami with windows hidden. All windows should come back.
- [ ] With two displays: unplug one and check the Restore / Keep Current prompt on reconnect.
- [ ] Sleep and wake the Mac, then check Stages still hold.

## 7. If something goes wrong

| Symptom | Try |
|---|---|
| A window is missing | `⌃⌥⌘R`, or quit Tatami |
| Shortcut does nothing | Is managing started? Does another app use that combo? Try the Classic preset in Preferences |
| Windows jump or fight | Another window manager or Stage Manager is still running |
| A window peeks out at a corner | Parked windows keep 1 pt visible. This is expected |
| An app window won't move off screen | Tatami minimizes it instead. This is expected |
| Accessibility was revoked | Re-enable it; parked windows return on their own |

Data lives in `~/Library/Application Support/Tatami/`. For anything that breaks, note the app, what you pressed, and what happened.
