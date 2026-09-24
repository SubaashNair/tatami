# AI Organizer (BYOK) implementation plan

Status: decisions settled (design review 2026-09-24), ready to build. Covers PRD AIO-01 to AIO-04, AIO-06, AIO-07, AIO-09, AIO-10, scoped to arrangement only.

## Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Distribution | Personal builds for now. Sign with Apple Development identity (via `TATAMI_SIGN_IDENTITY`), ad-hoc fallback. No App Sandbox. |
| 2 | Interaction | One-shot prompt, preview, Apply/Discard. "Ask Again" includes the previous plan summary for lightweight refinement. No chat history. |
| 3 | Output format | Prompt for JSON, tolerant parser, one automatic retry that feeds the parse error back. No provider-specific structured output. |
| 4 | Invalid actions | Drop invalid actions and anything that depends on them (cascading). Preview lists every dropped action with a reason. Apply disabled if nothing valid remains. |
| 5 | Paused management | Apply always works. Preview notes "Stages take effect when you start managing" when paused. |
| 6 | Title privacy | Per-provider "Send window titles" toggle, default on, shown in the disclosure sheet. |
| 7 | Shortcut conflict | Fix first: Control+Option becomes the default preset. |
| 8 | Preset migration | Replace `europeanShortcuts: Bool` with `shortcutPreset` (`standard` = Control+Option, `classic` = Option only). All existing files migrate to `standard`. Standard cycle/dashboard/arrange move to Control+Option+Command+arrows. |
| 9 | Panel location | Floating Spotlight-style panel for the hotkey, same SwiftUI view also reachable from a sidebar section. |
| 10 | Hotkey | Control+Option+Z (Control+Option+Command+Z in Classic), registered only while managing. |
| 11 | Stale windows | At Apply, actions whose window has closed are skipped and reported. New windows are left alone. |
| 12 | Undo | Single-slot undo, same as today. A later manual action replaces the AI undo. |
| 13 | Default models | Anthropic defaults to `claude-haiku-4-5`. Other presets: fetch model list after the key is entered, remember the choice. |
| 14 | Cancel | 60 s timeout plus Cancel button (`Task.cancel()`). |
| 15 | Displays | `snap` takes an optional 1-based `display` index, validated against current displays. |
| 16 | Build order | Five commits, tests green after each (see Build order). |
| 17 | Panel dismissal | Escape, outside click, or hotkey hides the panel and keeps an unapplied plan. Successful Apply closes the panel and posts "Arrangement applied, Undo available". |

## Scope

The AI may:

1. Create a Stage (name 1 to 60 characters, 9 Stage limit).
2. Rename a Stage.
3. Assign a window to a Stage.
4. Snap a window into one of the 16 `SnapZone`s, optionally on another display.

The AI may not delete Stages, change rules, exclusions, preferences, or shortcuts, or launch/close apps.

Out of scope: managed AI service, Recipes (AIO-05), temperature (AIO-11), streaming, chat history.

## Providers (2 adapters)

| Adapter | Wire format | Presets |
|---|---|---|
| `AnthropicProvider` | `POST /v1/messages`, `x-api-key`, `anthropic-version` | Anthropic |
| `OpenAICompatibleProvider` | `POST {base}/chat/completions`, `Authorization: Bearer` | OpenAI, Gemini (OpenAI-compatible endpoint), DeepSeek, OpenRouter, Ollama (`localhost:11434/v1`), LM Studio (`localhost:1234/v1`), Custom URL |

Presets are data (name, base URL, default model, needsKey, isLocal). Model list via `GET /v1/models`; the model field stays free text with the list as suggestions, so a failed fetch never blocks use. Local presets need no key and skip the cloud disclosure.

## Data sent

Per window: short ref (`w1`, `w2`...), app name, bundle ID, title (unless disabled per decision 6), current Stage name, display index, frame. Plus Stage names and display sizes. Excluded (always visible) apps are omitted. The ref table stays local, so the model cannot invent plausible IDs.

Before the first request to a cloud preset, a sheet names the destination host, lists these fields, and shows the titles toggle.

## Plan format

```json
{
  "summary": "Build work on the left, chat on the side screen.",
  "actions": [
    { "type": "createStage", "name": "Build" },
    { "type": "assign", "window": "w3", "stage": "Build" },
    { "type": "snap", "window": "w3", "zone": "leftTwoThirds" },
    { "type": "snap", "window": "w5", "zone": "maximize", "display": 2 }
  ]
}
```

Stages are referenced by name so a Stage created earlier in the plan can be targeted.

## Validation (TatamiCore, pure and tested)

`AIPlan.parse(_ text: String) throws -> AIPlan`: extract the first JSON object (tolerates code fences and prose), decode, reject unknown action types per action rather than per plan.

`AIPlan.validate(against: PlanContext) -> ValidatedPlan` with `valid: [Action]` and `dropped: [(Action, reason)]`:

1. Window ref exists.
2. Stage name exists, or was created by a still-valid earlier action (cascade: a dropped `createStage` drops its dependents).
3. Stage count after creation is 9 or fewer; names 1 to 60 characters, not duplicates.
4. `zone` is a valid `SnapZone`; `display` is within 1 to display count.
5. At most 200 actions considered.

## Apply and undo

`AppModel.apply(_ plan: ValidatedPlan)`: take `snapshot(name: "Before AI arrangement")`, then run the actions through internal variants of `addStage`, `renameStage`, `send`, `snap` that skip their own undo and visibility work, then one `applyVisibility`, one `persist`. Windows closed since the request are skipped and counted (decision 11). Undo is the existing `undo()`.

## Secrets

`KeychainStore` (`SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`), service `app.tatami.mac.ai`, account = preset ID. Keys never enter `WorkspaceState`, logs, or exports. Non-secret config lives in an optional `ai: AIConfig?` on `WorkspaceState` (selected preset, custom base URL, model per preset, send-titles per preset, disclosure acknowledged per preset).

## Network and errors

`URLSession`, 60 s timeout, off the main actor, cancellable. Errors map to plain messages: missing key, 401/403 bad key, 429 rate limit, offline or local server not running, unparseable after retry. The workspace is never touched on error.

## Build order

1. `git init`, `.gitignore` check, signing identity in `package_app.sh`, README note on the `~/Documents` codesign issue (`--scratch-path`).
2. Shortcut presets and migration (decisions 7, 8, 10 reserved key). Test: legacy file with `europeanShortcuts` decodes to `standard`.
3. `Sources/TatamiCore/AIPlan.swift` plus `Tests/TatamiCoreTests/AIPlanTests.swift`, tests first.
4. `Sources/Tatami/AIProvider.swift`: presets, two adapters, Keychain, retry, cancel.
5. `AppModel` apply refactor, `AIOrganizerView.swift`, floating panel, sidebar entry, AI settings box, hotkey.

Estimated size: about 700 lines including tests.

## Test plan

- [ ] Parse: bare JSON, fenced, after prose, malformed, unknown action type.
- [ ] Validate: unknown window ref, unknown Stage, create-then-use, cascade drop, 10th Stage, duplicate name, bad zone, bad display, action cap.
- [ ] Prompt builder: includes refs and Stage names, omits titles when disabled, omits excluded apps.
- [ ] Legacy `workspace.json` (no `ai`, has `europeanShortcuts`) decodes.
- [ ] Manual: Anthropic, OpenAI, Ollama each produce an applicable plan; Undo restores; bad key shows a clear error and nothing moves; cancel works; export contains no key; panel dismissal keeps plan.

## Other findings (not in this work)

1. **Main-thread AX polling.** `scan` runs every 2 s on the main actor with a 0.2 s timeout per app; one hung app stalls UI and hotkeys. Move off main or adopt the AX observer pipeline (milestone 1).
2. **Recovery can unminimize user windows.** `recoverPreviousSession` unminimizes every title match, including user-minimized windows. Low impact.
3. **View holds model logic.** Saved workspace rename/delete and rule edits mutate `model.state` directly in `Dashboard.swift`.
