# The `tatami` command

Run the same actions as the keyboard shortcuts from a terminal or a script. It talks to the running Tatami app over a private local socket. It cannot run programs, read files or reach the network.

## Install

1. Build and open the app: `bash scripts/package_app.sh`, then open `dist/Tatami.app` (move it to Applications first).
2. Choose **Install Command Line Tool…** from the Tatami menu bar menu, or **Install Command…** in Preferences. This links `~/.local/bin/tatami` to the copy inside the app, with no administrator password.
3. Make sure `~/.local/bin` is on your `PATH`.

Command-line control is on by default. Turn it off with **Allow command-line control** in Preferences.

## Commands

| Command | What it does |
|---|---|
| `tatami room <1-9\|next\|prev>` | Switch Room |
| `tatami send <1-9>` | Send the focused window to a Room |
| `tatami focus <left\|right\|up\|down>` | Focus the pane or window that way |
| `tatami move <left\|right\|up\|down>` | Move the window to the pane that way, or swap in Freeform |
| `tatami window <next\|prev>` | Focus the next or previous window across displays |
| `tatami pane <1-9>` | Focus a pane by its tab bar number |
| `tatami move-to-pane <1-9>` | Move the focused window into a pane by number |
| `tatami float` / `float-app` | Float or tile the focused window, or all windows of its app |
| `tatami rotate` | Turn the focused pane's split the other way |
| `tatami tiles` | Switch the focused display between Tiles and Freeform |
| `tatami display <next\|prev>` | Send the focused window to another display |
| `tatami undo-layout` | Undo the last layout change |
| `tatami rescue` | Bring every hidden window back and pause |
| `tatami start` / `pause` | Start or pause window management |
| `tatami home <1-9> <1-9\|none>` | Make a Room live on a display (numbers from `tatami list rooms` and `tatami list displays`), or `none` to clear it |
| `tatami list <windows\|rooms\|displays> [--json]` | Show what Tatami sees |
| `tatami status [--json]` | Managing or paused, and the version |

`tatami help` prints the same table. Words are case-insensitive. Rooms used to be called Stages, so `tatami stage` and `tatami list stages` still work, but the JSON field is now `room`.

The focused window is the one in the frontmost app. Run from Terminal, that is the terminal itself, so for window actions bind the command to a key in your shortcut tool or use `sleep 2; tatami ...` to try it.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Done |
| 1 | The app refused or the action failed |
| 2 | Bad usage |
| 3 | Tatami is not running, or command-line control is off |
| 4 | No answer in time, or a reply this version does not understand |

Some actions that cannot apply (for example `display next` with one display) print a message and still exit 0.

## Security

- The socket is at `~/Library/Application Support/Tatami/tatami.sock`. The folder is mode 0700 and the socket 0600. A folder owned by someone else, or a symlink, is refused.
- Every connection is checked to come from your user, on both sides.
- Requests are limited to 64 KB, 16 arguments of 256 bytes. A client gets 2 seconds in total to send its request, and at most 8 clients are served at once.
- Window titles in output have control characters removed, so a web page title cannot inject terminal escape codes.
- Any process running as you can use the command, including ones without Accessibility access. If that matters to you, turn the setting off.
- The protocol is versioned (`version` 1, one JSON line each way), so the app and the command refuse to guess when they differ.
