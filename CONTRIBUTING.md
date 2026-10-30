# Contributing to Tatami

Thanks for helping. Tatami is an alpha, keyboard-first macOS window manager, so bug reports from real setups (especially several displays and unusual apps) are as valuable as code.

## Ground rules

- **Keyboard first.** Every feature needs a keyboard path. The mouse is an optional extra, as in AeroSpace.
- **Safe by design.** Never lose a user's window. Hidden windows are journaled before anything moves. Do not weaken that.
- **Local first.** No telemetry and no network traffic except an AI request the user starts. The `tatami` command stays on a same-user local socket and never runs programs or reads files.
- **No secrets in the repo.** API keys live in the Keychain.

## Build and test

Requires macOS 14+ and Swift 5.10 (Xcode 15.4 or later).

```bash
swift build
swift test                 # unit tests, no screen or permissions needed
bash scripts/package_app.sh   # builds dist/Tatami.app (ad hoc signed unless TATAMI_SIGN_IDENTITY is set)
```

Set `TATAMI_SIGN_IDENTITY` to a stable code signing identity if you rebuild often. Otherwise macOS asks for the Accessibility permission again after every build.

`bash scripts/ax_integration.sh` runs opt-in checks against real windows. It needs Accessibility and an idle desktop: another app taking focus makes it flaky, so rerun before calling a failure a bug.

## Where code goes

| Folder | What belongs there |
|---|---|
| `Sources/TatamiCore` | Pure logic: Stages, pane layouts, focus by position, display order, routing, settings, the command protocol. Needs a unit test first. |
| `Sources/Tatami` | The app: Accessibility, windows, shortcuts, views. Keep decisions out of here; wire them to `TatamiCore`. |
| `Sources/TatamiCLI` | The `tatami` command. |
| `Tests/TatamiCoreTests` | XCTest suites for the core. |

Write the test first, make it fail, then make it pass. Prefer new immutable values over mutating existing ones, keep functions small, and handle errors instead of swallowing them.

## Pull requests

1. Branch from `main`. Keep the change focused.
2. `swift build` and `swift test` must pass, with no new `print` calls in the app.
3. Use conventional commit messages: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`, `ci:`.
4. Describe what changed, why, and how you tested it. Say if you could not test on several displays.
5. Update the README or `docs/` when behaviour or shortcuts change.

## Reporting bugs and security issues

Use the issue templates for bugs and ideas. For anything security related, follow [SECURITY.md](SECURITY.md) and do not open a public issue.

By contributing you agree that your work is released under the [MIT License](LICENSE).
