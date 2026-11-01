# Security policy

Tatami is an alpha. It moves other apps' windows through the macOS Accessibility API and exposes a local command-line socket, so security reports are welcome.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private reporting: **Security** tab, then **Report a vulnerability** (https://github.com/SubaashNair/tatami/security/advisories/new). Include the version (`tatami status`), your macOS version, and steps to reproduce.

You can expect an acknowledgement within a few days. Fixes ship in the next alpha, with credit if you want it.

## Supported versions

Only the latest release and `main` are supported while Tatami is in alpha.

## What Tatami does, so you can judge impact

- **Accessibility permission:** needed to read and move windows. Tatami has no network code except an AI request you start, to the provider you chose.
- **Command-line socket:** `~/Library/Application Support/Tatami/tatami.sock`, in a folder with mode 0700, socket 0600. Every connection is checked to come from your own user. Requests are size and time limited, with at most 8 clients at once. The command set is a closed list of window actions and read-only queries; nothing can run a program, read or write files, or reach the network. Any process running as you can use it, so turn it off with **Allow command-line control** in Preferences if that matters to you.
- **AI Organizer:** your API key is stored in the Keychain. Window titles and app names are sent only when you start an AI request.
- **Window recovery:** real window positions are journaled before windows are hidden, so a crash does not leave them lost.

## Out of scope

- Attacks that already need code running as your user with Accessibility permission.
- Issues in other apps or in macOS itself.
