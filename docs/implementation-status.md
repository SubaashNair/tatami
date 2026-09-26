# Implementation status — 0.1

The PRD is the long-term product specification. This first milestone establishes a runnable application and actual OS window control.

## Architecture

- `TatamiCore`: Codable product state, validation, routing precedence, and display geometry. Independent of UI and Accessibility.
- `WindowService`: Accessibility discovery, per-window visibility, layout application, focus, display coordinates, and recovery journal.
- `AppModel`: state persistence, operations, undo, saved arrangements, rules, settings backup, permissions, and lifecycle.
- `Hotkeys`: Carbon hotkey registration and action dispatch.
- `Dashboard`: native workspace UI, window list, Stage cards, snapping, routing, and preferences.
- `TatamiApp`: AppKit lifecycle, app menu, menu-bar status item, and dashboard window.

## Deliberate scope decisions

1. All nine Stages are available without a fabricated payment flow. Licensing will come after the core product is reliable.
2. ~~Stage hiding uses native minimization~~ Superseded by M1: windows are parked off screen with a journal, crash recovery, and a minimize fallback. See [m1-engine-plan.md](m1-engine-plan.md).
3. Stage selection is a preview until the user explicitly starts management. Existing windows are initially assigned to the active Stage rather than automatically classified.
4. Saved Workspace loading moves matching open windows. App relaunch, missing-document recreation, and full display mapping require a later identity/reconciliation layer.
5. Shortcuts have two presets; arbitrary recording and gesture support are later milestones.
6. Window discovery currently reconciles every two seconds. An AX observer-driven event pipeline is a later performance improvement; the prototype does not claim the PRD's latency or idle-CPU targets.

## Next milestones

1. AX observer pipeline, durable window matching, stable display reconciliation, and automatic checkpoint recovery.
2. Tiling tree model and tests, tabbed-pane overlay, native-tab identity, per-monitor mode storage, and layout editor.
3. Stage Strip hot edge, drag-to-Stage assignment, and configurable Action Wheel.
4. ~~AI provider adapters, structured plan validation, preview/apply transaction, and Keychain secrets~~ (done, see [ai-organizer-plan.md](ai-organizer-plan.md)). Remaining: Recipes, temperature, managed AI.
5. Signing/notarization, updates, entitlements, packaging, and supported-device QA.

## Validation boundary

Automated tests cover Stage invariants, input validation, ordered routing, exclusion precedence, snap geometry, grids, coordinate conversion, rescue bounds, and persistence round trips. Successful builds do not prove cross-app Accessibility behavior. Hardware/OS integration needs manual verification with permission granted and representative applications.
