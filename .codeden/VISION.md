# Vision

Tatami is a keyboard-first window manager for macOS. Each task gets a Room that spans every display; windows tile into panes with tabs; and the whole desk comes back exactly as it was after a switch, a restart, sleep or a display change. It is native, local first and safe by design: a user's windows are never lost. The factory scores every piece of work against this file.

## Goals
For the next three to six months:
- Ship a public stable that installs cleanly on any Mac: Developer ID signed, notarized, and built and published by CI.
- Make window state survive real life: sleep and wake, docking and undocking, full screen apps and other Spaces, identical monitors, and apps hidden with ⌘H. After any of these, every window is visible or recoverable, in its own Room and pane.
- Keep shortcuts instant when an app is slow: a hung app must never block keys or Room switches.
- Make the first run succeed within minutes, with no configuration file: grant Accessibility, have at least two Rooms, switch Rooms and move a window.
- Give AeroSpace users a smooth way in: import their config and keep their muscle memory.
- Keep CI green on every pull request, and the desktop integration test passing.

## Target users
- **Multi-project professionals on two or more displays** (developers, designers, researchers): switch the whole desk between projects and find every window where they left it, including after docking or sleep.
- **Keyboard-first power users, many coming from AeroSpace, i3 or yabai**: predictable shortcuts for focus, move, tile, float and send to display, without a config file or disabling SIP.
- **Mouse and trackpad users**: see every Room and drag windows and tabs where they belong, with the same actions the keys offer.
- **Privacy-conscious users**: no account and no telemetry. AI arrangement runs only when they ask, with their own provider or a local model.

All on macOS 14 or later, Apple silicon first.

## Principles
- Small, well-tested changes.
- Keep the public API stable. That covers the `tatami` commands (their output, `--json` fields and exit codes), the default shortcuts in both presets, and the saved settings, which every new version must still read.
- Never lose a window. Record a window's real position before hiding it, and when in doubt, show windows rather than keep a layout perfect.
- Keyboard first: every feature has a keyboard path, and the mouse is an optional extra.
- Local first: no network traffic except an AI request the user starts.
- Every automatic behaviour has an escape hatch: undo, float, exclude, pause or Rescue.
- Show a preview before broad changes (AI plans, workspace loads, imports) are applied.
- Decisions live in `TatamiCore` as pure, tested logic. The app layer only connects them to Accessibility and the UI.
- No third-party dependencies: standard macOS APIs only.
- Follow `docs/brand.md`, including its contrast rules.

## Out of scope
- Telemetry, analytics, crash reports sent anywhere, or any network call the user did not start.
- Requiring SIP to be disabled; private window server APIs; kernel or system extensions; injecting code into other apps.
- Reading screen pixels, keystrokes or document contents, including for AI.
- Syncing windows or settings between Macs; accounts or cloud services.
- Versions for Windows, Linux, iPhone or iPad.
- Replacing Finder, the Dock or Mission Control.
- A scripting language, or `tatami` commands that run programs or read and write files.
- A text configuration file as the main way to use Tatami.
- Features with no keyboard path.
- Copying BetterStage's or AeroSpace's code, branding, text or assets.
- New third-party dependencies.

## Quality bar
- Every behaviour change comes with tests. `TatamiCore` logic is tested first, and the test fails without the change.
- CI is green before merge.
- `swift build` has no new warnings, and `swift test` and `swiftlint lint --strict` pass.
- Changes to the window engine (hiding, showing, recovery, displays, full screen) say how they were checked on real windows, including a run of `scripts/ax_integration.sh` on an idle desktop where it applies.
- No `print` in the app. Errors are handled and shown to the user, never silently dropped.
- The README and `docs/` are updated whenever behaviour or shortcuts change.
- Commit messages follow the conventional format (`feat:`, `fix:`, …).

## Protected areas
Paths (globs in backticks) and topics that always need a human. The factory never merges
changes that touch them; they go to your inbox.
- `.github/workflows/**`
- `LICENSE`
- `SECURITY.md`
- `Package.swift`
- `.swiftlint.yml`
- `Tests/.swiftlint.yml`
- `scripts/package_app.sh`
- `Resources/Info.plist`
- `Sources/TatamiCore/CLITransport.swift`
- `Sources/TatamiCore/CLIProtocol.swift`
- `Sources/Tatami/AIProvider.swift`
- `docs/brand.md`
- `docs/icons/**`
- `Resources/AppIcon.icns`
- payments
- licensing
- signing, notarization and releases
- permissions: Accessibility, Screen Recording, entitlements and usage descriptions
- any new network request, telemetry, or data leaving the Mac
- the saved state format (`workspace.json`, `checkpoint.json`, `setups.json`, `recovery.json`): what is written, or how older files are read
- the recovery journal and window parking, where a bug can leave windows off screen
- default keyboard shortcuts and presets
- launch at login, and other defaults that change behaviour without asking
