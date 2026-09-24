# Tatami Product Requirements Document

## Native macOS workspace and window manager inspired by BetterStage

| Field | Value |
|---|---|
| Status | Draft for product review |
| Version | 1.0 |
| Date | 2026-09-23 |
| Platform | macOS 14 Sonoma and later |
| Working product name | Tatami |
| Reference product | BetterStage 2.0.5 public site, documentation, and how-to library |

## 1. Purpose and scope

This PRD defines a native macOS workspace manager that gives each project or activity a named, multi-monitor workspace. Users can switch their entire desk instantly, arrange windows manually or in managed tabbed panes, recover layouts after restarts and display changes, route apps automatically, and optionally ask an AI model to propose an arrangement.

The document is a black-box product specification based on BetterStage's public documentation and how-to material as reviewed on 2026-09-23. It describes observable behavior and then converts it into implementation-ready product requirements. It does not assert access to BetterStage source code or private design decisions, and it should not be used to copy BetterStage branding, visual assets, text, or proprietary code.

### Product thesis

macOS users who juggle multiple projects and displays do not merely need windows resized; they need their entire working context to change predictably. Tatami should make context switching feel instant, reversible, and safe while remaining approachable to people who do not want to maintain configuration files.

### One-sentence value proposition

Give every project a named workspace that spans all displays, remembers its layout, and returns exactly as you left it.

## 2. Reference-product analysis

### 2.1 What BetterStage is

BetterStage is a native Swift/AppKit macOS window and workspace manager. Its central abstraction is a **Stage**: a named collection of windows spanning every participating monitor. A stage remembers window membership, positions, and a per-monitor Window Mode. Switching stages hides the outgoing windows and reveals the incoming windows without a Spaces-style slide animation.

The reference product combines five layers:

1. **Context layer:** named Stages and saved Workspaces.
2. **Layout layer:** free-form Enhanced Native mode, managed TabStack panes, layout presets, and snap zones.
3. **Control layer:** keyboard, mouse, trackpad, menu-bar controls, Stages Bar, and a radial Snap Wheel.
4. **Automation layer:** app-routing rules, app/window exceptions, workspace continuity, and AI Staging.
5. **Commercial layer:** Free, lifetime Pro, optional managed AI, trials, device activation, and update channels.

### 2.2 Product strengths worth preserving

- A clear mental model: a project is a Stage; every display changes together.
- Fast direct access through numbered shortcuts instead of spatial desktop navigation.
- A choice between manual and managed layout behavior on each display.
- Strong mouse-first and keyboard-first control paths for the same actions.
- Local-first state and recovery, with cloud use limited to licensing and optional AI.
- Visual settings rather than mandatory configuration files.
- Graceful handling of difficult system events: app restart, sleep/wake, docking, monitor reconnection, missing windows, permission revocation, and unsaved-work prompts.
- Progressive monetization: a useful free tier, durable Pro unlock, and optional recurring AI service.

### 2.3 Reference limitations and opportunities

- The concepts of Stage, Workspace, Window Mode, layout preset, recipe, and app-routing rule create a substantial learning curve.
- The feature set is power-user oriented and can make Settings dense.
- Hiding windows by moving them off-screen is pragmatic but creates recovery and edge-leak risks.
- AI Staging can expose sensitive metadata such as titles, paths, and URLs to a provider.
- The experimental Custom Actions feature executes user-defined commands and therefore needs unusually clear trust boundaries.
- A maximum of nine Stages simplifies shortcuts but may frustrate users with many contexts.
- A first-party sync model is absent from the public feature set; settings backups are portable, but stage and workspace state are device-local.

Tatami should retain the reference product's depth while improving terminology, onboarding, diagnostics, and disclosure of state.

### 2.4 Reference commercial snapshot

As of the research date, BetterStage publicly advertises a permanent Free tier with three Stages and a seven-day no-card Pro trial. Lifetime Pro is listed at USD 19.99 for one Mac, USD 39.99 for three Macs, and USD 49.99 for five Macs, with future updates included. Eligible Free users can also invoke a 15-minute Pro preview once every 24 hours. The optional managed BetterStage AI service is listed at USD 4.99 monthly or USD 39 annually, covers up to three Macs, and includes 200 arrangements per month plus a 20-credit no-card trial. These prices are reference-market evidence, not committed Tatami pricing.

## 3. Goals, non-goals, and principles

### 3.1 Goals

- Let users create and switch among named, project-oriented workspaces across all connected displays.
- Preserve window membership, placement, layout, and display assignment reliably.
- Support both free-floating window management and automatic tiled panes with tabs.
- Offer equivalent keyboard, mouse, and trackpad access for core actions.
- Recover safely after restart, sleep/wake, docking, undocking, and display changes.
- Enable deterministic automation through app-routing rules and optional natural-language arrangement.
- Operate with standard macOS APIs, System Integrity Protection enabled, and the minimum practical permissions.
- Provide a useful free tier and a coherent upgrade path.

### 3.2 Non-goals for the first public release

- Replacing Finder, Mission Control, or the macOS Dock.
- Managing windows inside virtual machines or remote desktops when macOS Accessibility cannot address them.
- Synchronizing live windows or workspace state between Macs.
- Reading document contents, screen pixels, or keystrokes for AI organization.
- Offering a general-purpose workflow automation language.
- Supporting Windows, Linux, iPhone, or iPad.
- Requiring users to disable SIP or install kernel/system extensions.

### 3.3 Product principles

- **The user's windows are never expendable.** Failure should restore visibility before preserving layout perfection.
- **Preview destructive or broad changes.** AI plans, workspace loads, imports, and clean loads require review.
- **Every automatic behavior has an escape hatch.** Users can undo, exclude, float, pause, or disable automation.
- **Local by default.** Workspace state, rules, layouts, and credentials stay on the Mac unless the user explicitly invokes a network-backed feature.
- **Input parity.** Core functions should be reachable by keyboard and at least one pointer-based path.
- **No mystery state.** The app should explain which Stage, display, Window Mode, rule, or recovery operation controls the visible result.

## 4. Target users and jobs to be done

### Primary persona: multi-project professional

A developer, designer, researcher, or operator who moves between several projects each day and regularly uses two or more displays.

Jobs:

- “When I change projects, restore the entire desktop context without making me reopen or rearrange everything.”
- “Let me keep communication or monitoring visible while the rest of my workspace changes.”
- “When I dock or undock, make every window usable without destroying the layout I will need later.”

### Secondary persona: keyboard-first power user

A user who expects deterministic shortcuts, directional focus, tiling, and minimal animation, but does not want to maintain a text configuration.

Jobs:

- “Let me switch context, move windows, focus panes, and retile without touching the mouse.”
- “Let me rebind controls without creating conflicts.”

### Secondary persona: visual organizer

A mouse or trackpad user who wants direct manipulation and visual previews rather than memorized shortcuts.

Jobs:

- “Show me what is in every workspace and let me drag windows where they belong.”
- “Put window actions under my pointer.”

### Tertiary persona: privacy-conscious AI user

A user who wants intelligent organization but needs control over provider choice and transmitted data.

Jobs:

- “Let me use my own provider or a local model.”
- “Show the proposed changes and the exact data class involved before moving anything.”

## 5. Product model and terminology

| Concept | Definition |
|---|---|
| Stage | A named set of windows spanning all staged displays. Only one Stage is active at a time. |
| Staged display | A monitor whose visible windows change when the active Stage changes. |
| Pinned display | A monitor with one always-visible workspace independent of Stage switching. |
| Window Mode | Per-Stage, per-display behavior: Freeform or Tabbed Tiling. |
| Freeform | Native floating windows plus snapping and manual arrangement. Equivalent to the reference product's Enhanced Native mode. |
| Tabbed Tiling | A resizable pane tree where each pane contains one or more windows presented as tabs. Equivalent to TabStack. |
| Layout preset | Reusable pane geometry without fixed app/window assignments. |
| Workspace checkpoint | Automatically maintained local recovery state for the latest desk. |
| Saved Workspace | A user-named, reusable snapshot of Stages, displays, modes, layouts, and reopenable apps. |
| Routing rule | Ordered match criteria that place a new window into a Stage or pinned display. |
| Window behavior rule | A remembered instruction to manage, float, or auto-detect matching windows. |
| AI Recipe | Reusable natural-language instructions for AI Staging. |

## 6. Information architecture

Tatami runs primarily as a menu-bar application and exposes these surfaces:

- Onboarding and permission setup.
- Menu-bar menu and configurable status items.
- Stage Strip: transient visual overview of all Stages.
- Action Wheel: radial context menu shown at the pointer.
- AI Organizer panel.
- Workspace save/load preview and recovery dialogs.
- Settings with sections for General, Stages, Window Modes, Workspaces, Action Wheel, Shortcuts, AI, App Routing, App Exceptions, Displays, Backup, License, Updates, and Support.

## 7. Functional requirements

Priority labels: **P0** is required for a reliable core release, **P1** completes the parity product, and **P2** is an advanced or experimental extension.

### 7.1 Installation, onboarding, and permissions

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| ONB-01 | P0 | Support Apple Silicon and Intel Macs on macOS 14+. The application must be native Swift/AppKit and run with SIP enabled. |
| ONB-02 | P0 | Install as a standard signed/notarized macOS app and run from the menu bar without requiring a persistent Dock icon. |
| ONB-03 | P0 | Explain why Accessibility permission is needed before requesting it. Provide a deep link to the correct System Settings pane and detect permission changes without relaunching when possible. |
| ONB-04 | P0 | Do not require Input Monitoring or Screen Recording for standard features. If a visible Terminal action requires Automation permission, request it just in time. |
| ONB-05 | P0 | Detect macOS Stage Manager and guide the user to turn it off before enabling Stage visibility management. |
| ONB-06 | P0 | First run creates three editable example Stages—such as Work, Comms, and Browse—and offers to classify current windows by app. The user can skip automatic classification. |
| ONB-07 | P1 | Detect Option-heavy keyboard layouts and recommend a European shortcut preset while allowing later switching without overwriting customized bindings. |
| ONB-08 | P1 | Offer a stable or beta update channel and expose the installed version in Settings. |

### 7.2 Stages and navigation

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| STG-01 | P0 | Users can create, rename, reorder, switch, and delete Stages. Deleting a Stage moves its windows to the active Stage; no managed window becomes unreachable. |
| STG-02 | P0 | A Stage spans every staged display and stores window membership, window frame, display identity, z-order hints, and Window Mode per display. |
| STG-03 | P0 | Switching changes all staged displays as one transaction and avoids decorative slide animations. The active Stage persists across app restarts. |
| STG-04 | P0 | Provide direct switching for Stages 1–9, previous/next navigation, and forward/backward cycling. Reordering changes the numeric mapping and visibly communicates it. |
| STG-05 | P0 | Move the focused window to any Stage without switching by default. A preference may follow the moved window to the destination. |
| STG-06 | P1 | Auto-switch when a window from an inactive Stage receives focus. Users can disable this behavior. |
| STG-07 | P1 | Optionally scope Cmd+` cycling to windows belonging to the active Stage. |
| STG-08 | P1 | Merge all Stages into the active Stage with confirmation and undo. |
| STG-09 | P1 | Apps excluded from staging remain visible across all Stages and take precedence over routing rules. |
| STG-10 | P0 | Free packaging supports up to three Stages; Pro supports up to nine. When a limit is reached, preserve all existing state and offer upgrade or merge paths. |

### 7.3 Stage Strip

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| BAR-01 | P0 | Show all Stages as named cards with live window thumbnails and a distinct active state. Thumbnails update after window moves/resizes. |
| BAR-02 | P0 | Open by keyboard and by an optional top-edge hot zone. Allow a 0–2 second activation delay and an option to ignore the MacBook notch region. |
| BAR-03 | P0 | Clicking a card switches Stage; dragging a card reorders it; dragging a window to a card reassigns it. |
| BAR-04 | P1 | Context actions include create, rename, delete, and access to relevant Window Mode controls. |
| BAR-05 | P1 | Optionally show a click-through indicator for about 1.5 seconds after a switch. |
| BAR-06 | P0 | Dismiss on Escape, outside click, repeat shortcut, or completed Stage selection without trapping keyboard/mouse input. |

### 7.4 Freeform window management and snap zones

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| SNP-01 | P0 | Freeform mode preserves normal macOS window movement and sizing while tracking Stage membership. It is the default for new Stages. |
| SNP-02 | P0 | Provide 16 zones: four halves, four quarters, three thirds, three two-thirds positions, centered half-width/half-height, and maximize. |
| SNP-03 | P0 | Trigger zones by configurable shortcuts and optional edge drag. The target display is determined from the window/pointer context. |
| SNP-04 | P1 | Retile a disorganized Freeform display into a balanced grid; invoking Retile on an already structured grid may re-stack windows as a centered deck. |
| SNP-05 | P0 | Snapping accounts for the visible work area, menu bar, Dock, notch, and user-defined per-edge screen padding. |

### 7.5 Tabbed Tiling mode

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| TIL-01 | P0 | Each display may independently use Tabbed Tiling for each Stage. The layout is a resizable pane tree; every pane may be empty or contain one or more window tabs. |
| TIL-02 | P0 | Users can split a pane left/right/above/below, remove empty panes, join a window as a tab, move one tab, move an entire tab group, swap panes, and insert a window at a divider or edge. |
| TIL-03 | P0 | Tabs change only the visible member of their pane. When the selected tab closes, moves, or floats, select the most recently used remaining tab. |
| TIL-04 | P0 | Divider resizing affects only adjacent panes. Preserve independent row and column boundaries where the pane tree permits it. |
| TIL-05 | P1 | Configure split drop-zone size from 0–40%, enable/disable normal swap zones, and allow Option-drag as an explicit swap override. |
| TIL-06 | P0 | Directional focus and directional move commands traverse panes and continue to the adjacent display when geometry allows. |
| TIL-07 | P0 | Provide zoom/restore for a pane. Switching tabs within the same pane keeps it zoomed; selecting another pane restores the full layout first. |
| TIL-08 | P1 | Launch an app into a chosen pane. Prefer creating a new window when the app supports it; otherwise move a suitable existing window. |
| TIL-09 | P1 | Allow quit and relaunch from a tab context menu while respecting app-native unsaved-work prompts. |
| TIL-10 | P0 | Handle native-tab applications such as Terminal without phantom duplicates or identity loss across Stage switches. Promptly remove stale Electron windows. |
| TIL-11 | P1 | Allow a file to be dropped onto a background tab and deliver the drop to the correct underlying window when supported. |
| TIL-12 | P0 | Choose new-window placement: Automatic, Active Pane, Adjacent Pane with direction, or Own Pane. Explicit routing, restore, native-tab identity, and “Launch Here” take precedence. |
| TIL-13 | P0 | Per-window behavior is Automatic, Manage in Layout, or Keep Floating. Users can persist a rule by app with an optional title condition. |
| TIL-14 | P1 | Retile balances the pane tree; Reflow as Grid creates a balanced grid; Even Out normalizes adjacent sizing; Undo reverses the most recent layout mutation. |
| TIL-15 | P1 | Raise floating/untracked windows above managed panes without changing membership or exposing parked background tabs. |
| TIL-16 | P1 | Appearance settings include Comfortable, Compact, and Custom styles; pane/tab padding; pane gaps; screen padding; pane/tab-bar opacity; tab height; compact/expanded tab width; active/inactive text colors; accent-colored selection; and empty-pane close-button visibility. |

### 7.6 Layout presets

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| LAY-01 | P1 | Ship five geometry-only presets: One Full Screen, Split View, Top/Bottom, Focus + Stack, and Four Corners. Presets must not bind to specific applications. |
| LAY-02 | P1 | Users can create, name, duplicate, edit, and delete custom presets in a visual pane editor. Built-ins can be duplicated but not deleted. |
| LAY-03 | P1 | Apply a preset from Settings, a shortcut, or the Action Wheel, and optionally choose a default preset for entry into Tabbed Tiling. |
| LAY-04 | P1 | Choosing a default preset is independent from choosing the default Window Mode. Existing Stages are not silently changed. |

### 7.7 Workspace continuity and saved workspaces

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| WSP-01 | P0 | Maintain a local checkpoint of Stages, active Stage, window identities/frames, display assignments, modes, pane trees, selected tabs, and tab groups. |
| WSP-02 | P0 | Reconcile the checkpoint after app restart, Mac wake, docking/undocking, and display topology changes. Wait for displays and apps to settle before moving windows. |
| WSP-03 | P0 | Recovery progress must not block normal use longer than necessary. Provide warnings and undo where feasible; allow routine recovery toasts to be silenced. |
| WSP-04 | P0 | When a display disconnects, make its windows usable on remaining displays while preserving their remembered original arrangement. In Tabbed Tiling, integrate recovered windows into available panes. |
| WSP-05 | P0 | When a known display returns, show a nonblocking Restore / Keep Current Layout decision on the display containing the pointer. Restore only after explicit selection. |
| WSP-06 | P1 | Let Pro users save a named snapshot of the current Stage or all Stages, including display/mode/layout data and reopenable applications. |
| WSP-07 | P1 | Loading shows a preview, continuous progress, and actionable failures. It may request missing app windows from applications that can create them. Empty saved Stages may be skipped. |
| WSP-08 | P1 | If a saved display is missing, allow mapping to a connected destination and choosing Create Stages or Merge. Prevent creating Stages beyond the plan limit. |
| WSP-09 | P1 | Saved Workspaces support rename, delete, and direct shortcut assignment. A single-key shortcut is allowed only within this explicit workspace binding surface and must be conflict checked. |
| WSP-10 | P1 | Optional Clean Load requests apps and Stages outside the saved Workspace to close/remove. Never force-quit; if an app refuses to quit, stop and explain. The option resets after each attempt. |

### 7.8 Multi-monitor and pinned displays

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| DSP-01 | P0 | Treat staged displays as one workspace for switching, while computing layout independently per display. Stage switching does not move a window to a different display. |
| DSP-02 | P0 | Persist display identity using stable hardware signals such as model, serial, resolution, and relative position rather than transient macOS display IDs. |
| DSP-03 | P0 | Detect hot-plug events without restart and restore the matching arrangement after topology settles. |
| DSP-04 | P1 | Pro users can mark each monitor Staged or Pinned. A pinned display remains visible across Stage switches and supports normal Window Modes. |
| DSP-05 | P1 | Pinning merges that monitor's windows into its independent always-visible workspace; unpinning safely returns them to Stage management. |
| DSP-06 | P0 | Hidden inactive windows are parked off-screen in a recoverable way. Prefer a safe local display corner when configured; fall back to a global safe location when geometry would leak shadows or rounded corners. |
| DSP-07 | P0 | Provide a Rescue Windows action that returns all controlled windows to visible bounds without requiring the current layout state to be valid. |

### 7.9 Action Wheel

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| WHL-01 | P1 | Show a radial menu at the pointer for the targeted window. Default triggers include middle-click toggle and four-finger trackpad tap toggle. |
| WHL-02 | P1 | Support multiple simultaneous triggers: middle-click hold/toggle, four- or five-finger tap/click, Ctrl+Option hold with configurable delay, and custom keyboard/mouse combinations. Each trigger independently uses hold or toggle behavior. |
| WHL-03 | P1 | Provide an inner ring for directional placement and an outer ring for adaptive full/zoom, Retile, Send to Stage, Switch Stage, Workspaces, Window Modes, More Actions, and Settings. |
| WHL-04 | P1 | Actions adapt to the active Window Mode. Freeform directions snap; Tabbed Tiling directions move to adjacent panes. Disabled actions explain why they are unavailable. |
| WHL-05 | P1 | Users can reorder, replace, or hide slots; configure up to 12 slots per ring and 16 per submenu; and select SF Symbols for slots/submenus. |
| WHL-06 | P1 | Offer a frosted native style and a high-contrast flat style with separate ring color controls. Respect Reduce Transparency and accessibility contrast settings. |
| WHL-07 | P2 | Pro users can create outer-ring custom submenus that contain approved built-in or Custom Actions. |

### 7.10 Shortcuts and input bindings

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| INP-01 | P0 | Every Stage, snap, focus, move, mode, retile, and workspace action can be rebound. Preserve separate keyboard, mouse-button, and trackpad bindings per action. |
| INP-02 | P0 | Settings provides search, a compact Stage binding editor, a visual snap-zone map, recorder fields, and inline conflict warnings. |
| INP-03 | P0 | Standard defaults include Option+1–9 to switch, Option+Shift+1–9 to send, Option+arrows/Tab for navigation, Option+N/X for Stage lifecycle, Option+B to cycle mode, Option+Down to retile, and Control+Option snap bindings. |
| INP-04 | P1 | A European preset adds Control only to Option-heavy number-row and loose-letter shortcuts. Switching presets leaves user-edited bindings intact. |
| INP-05 | P0 | Reject or explicitly resolve conflicts; never silently steal an existing Tatami binding. Surface likely system/app conflicts when detectable. |

### 7.11 App routing and exceptions

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| RTE-01 | P1 | Define ordered rules matching application identity, window title, or both. The first enabled match wins. Rules can be reordered, paused, edited, and deleted. |
| RTE-02 | P1 | Route new matching windows to Stage 1–9, optionally on a chosen display, or to a pinned display. A Stage destination may optionally trigger a follow switch. |
| RTE-03 | P1 | If a selected Stage does not exist, label it “will be created” and create all missing intermediate Stages at first match, subject to plan limits. |
| RTE-04 | P1 | Rules affect new windows by default; provide an explicit “Move existing windows now” action for retrospective application. |
| RTE-05 | P1 | If a target Stage is deleted, keep the rule disabled or warning-marked as “Stage not found” instead of redirecting unpredictably. |
| RTE-06 | P1 | Exception lists are independent: Exclude from Staging, Float in Window Modes, and Float Secondary Windows. App exclusions take precedence over routing. |
| RTE-07 | P1 | Reset restores curated default exceptions without deleting unrelated user settings. |

### 7.12 AI Organizer

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| AIO-01 | P1 | Provide a chat-style panel where users describe the desired workspace and @-mention apps, windows, Stages, displays, or modes. |
| AIO-02 | P1 | Build a snapshot from app name, window title, document path, URL host/path, display geometry, and system constraints. Never send file contents, screenshots, or keystrokes. |
| AIO-03 | P1 | Return a structured plan that may create named Stages, assign windows/displays, and choose Window Modes. Show the full proposed actions before anything moves. |
| AIO-04 | P1 | Users can refine the plan conversationally, apply it as one transaction, and undo the applied transaction in one step. |
| AIO-05 | P1 | Save, select, create, duplicate, rename, delete, and set a default Recipe. Show the exact prompt and mentions that will be sent. |
| AIO-06 | P1 | Support provider presets for major OpenAI-compatible services, Anthropic-native formatting, Azure OpenAI, local Ollama/LM Studio, and a Custom OpenAI-compatible endpoint. |
| AIO-07 | P1 | Store keys per provider in Keychain, fetch accessible model lists where supported, preserve keys when switching, offer regional endpoints where needed, and provide Test Connection. |
| AIO-08 | P1 | BYOK requests go directly to the selected provider. Managed AI is a separate service path that requires explicit subscription disclosure and usage accounting. |
| AIO-09 | P1 | Local providers operate offline. Cloud providers fail with a clear network/provider error without modifying the workspace. |
| AIO-10 | P1 | Before first cloud use, disclose that titles, paths, and URLs can contain sensitive information and identify the destination provider. |
| AIO-11 | P2 | Allow adjustable model temperature for compatible providers while keeping a conservative default. |

### 7.13 Custom Actions

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| ACT-01 | P2 | Support exactly four initial action types: Open Application, Open File, Run Command, and Run macOS Shortcut. Multi-step automation is out of scope. |
| ACT-02 | P2 | Verify saved app paths/bundle identity and file existence before execution. Allow custom SF Symbols where a native icon is not available. |
| ACT-03 | P2 | Background commands run with `/bin/zsh -f`, no shell startup files, no stdin/terminal, discarded output, and a user-selectable 1–60 second foreground deadline. |
| ACT-04 | P2 | Require confirmation on first run and after edits, or optionally every run. Editing command text invalidates previous trust. |
| ACT-05 | P2 | “Show in Terminal” hands process ownership to Terminal, clearly explains that Tatami can no longer stop it, and requests Automation permission only when used. |
| ACT-06 | P2 | Do not log command text/output or export Custom Action definitions/command files in a portable settings backup. Factory Reset removes them; ordinary settings reset preserves them. |

### 7.14 Settings, menu bar, backup, license, and diagnostics

| ID | Pri | Requirement and acceptance criteria |
|---|---:|---|
| SET-01 | P0 | Launch at Login defaults on and uses SMAppService. |
| SET-02 | P1 | Users can choose and reorder menu-bar items: logo, Stage index, Stage count/stepper, window count, Stage name, and per-display mode summary. At least one item remains enabled. |
| SET-03 | P0 | Export a versioned JSON settings backup containing portable preferences, input bindings, routing/exception/window rules, display preferences/nicknames, AI configuration without credentials, safe built-in wheel layout, and custom layout presets. |
| SET-04 | P0 | Never export license/device/account state, API keys, live Stages/windows, Saved Workspaces, or Custom Action command authority. |
| SET-05 | P0 | Validate import before mutation, ignore unknown future keys, replace known exported keys atomically, and offer relaunch. Failed validation leaves existing settings unchanged. |
| SET-06 | P0 | Reset Settings clears portable rules/layouts and restores defaults while retaining Stages, live windows, credentials, Saved Workspaces, and Custom Actions. Factory Reset is a separate, strongly confirmed operation. |
| SET-07 | P0 | License activation supports inspect, activate, deactivate, device-limit resolution, periodic verification, and a signed offline grace period. Losing Pro access never deletes user data. |
| SET-08 | P1 | Support a no-card Pro trial and a limited daily Pro preview. Show remaining time and degrade gracefully to Free without data loss. |
| SET-09 | P0 | Diagnostic log excludes secrets and command contents, is user-revealable, and records enough state transitions to diagnose permission, display, routing, and recovery failures. |
| SET-10 | P0 | If Accessibility permission is revoked, alert the user and restore every hidden/parked window to visible bounds before disabling management. |

## 8. Core user flows

### 8.1 First-run success flow

1. User launches Tatami.
2. The app explains the Stage concept and checks whether macOS Stage Manager is active.
3. User grants Accessibility permission from System Settings.
4. Tatami detects keyboard layout and recommends a shortcut preset.
5. User accepts or edits three starter Stages and chooses whether to sort current windows.
6. A guided overlay demonstrates switching, moving a window, opening the Stage Strip, and invoking the Action Wheel.
7. Success state: the user can switch among three visibly distinct Stages and recover all original windows.

### 8.2 Switch project context

1. User presses the shortcut for another Stage or selects it from the Stage Strip.
2. Tatami captures current geometry changes.
3. Outgoing windows are safely parked; incoming windows return to their assigned displays and selected tab state.
4. The menu-bar state updates; optional transient Stage indicator appears.
5. Focus goes to the last active valid window in the destination Stage.

### 8.3 Organize a display with Tabbed Tiling

1. User switches the current display to Tabbed Tiling.
2. Tatami offers built-in and custom layout presets unless an automatic default is enabled.
3. User drops windows into panes, onto tab bars, edges, or dividers.
4. The app previews join/split/swap targets before commit.
5. Every mutation is added to a bounded layout undo history.

### 8.4 Dock/undock recovery

1. Display topology changes.
2. Tatami waits for a stable topology and applications to settle.
3. Windows from unavailable displays become usable on remaining displays without overwriting remembered placement.
4. When the display returns, Tatami recognizes it and asks Restore or Keep Current Layout.
5. Restore replays the protected arrangement; Keep Current Layout updates the checkpoint intentionally.

### 8.5 AI arrangement

1. User opens AI Organizer and selects provider/Recipe.
2. The panel shows the metadata classes that will be sent and the selected destination.
3. User describes a workspace with optional mentions.
4. Tatami streams the response into a structured, validated plan.
5. User reviews and refines the plan.
6. Apply performs one atomic layout transaction; Undo restores the pre-apply snapshot.

## 9. State and data model

At minimum, the product needs these entities:

- `Stage`: id, name, order, lastFocusedWindowId, perDisplayModes.
- `DisplayIdentity`: stable fingerprint, nickname, staged/pinned role, current frame, topology signature.
- `WindowIdentity`: app bundle id, process id/session hints, accessibility id, title/path/url hints, native-tab identity, last known frame.
- `StageWindowMembership`: stageId or pinnedWorkspaceId, windowId, displayId, frame, z-order hint, floating state.
- `PaneNode`: split axis, ratio, children, pane id.
- `Pane`: ordered window tabs, selectedWindowId, empty state, zoom state.
- `LayoutPreset`: name, immutable built-in/custom marker, pane geometry tree.
- `Checkpoint`: timestamp, topology signature, active Stage, complete recoverable local state.
- `SavedWorkspace`: name, scope, display mappings, Stage snapshots, app reopen instructions.
- `RoutingRule`: ordered app/title match, enabled state, destination, follow behavior.
- `WindowBehaviorRule`: app/title match and Automatic/Managed/Floating behavior.
- `AIProviderConfig`: provider, endpoint, model, region, non-secret settings; secret stored separately in Keychain.
- `AIRecipe`: name, prompt, mentions, default marker.
- `ShortcutBinding`: action, input type, chord/gesture, preset provenance, customization marker.
- `CustomAction`: local-only type, target, icon, trust/confirmation policy.

Persistence must be versioned and migration-safe. Checkpoint writes should be debounced, crash-safe, and atomic.

## 10. System and quality requirements

### Performance

- P0: Direct Stage switching should complete perceptually instantly; target median under 150 ms for 20 windows and under 300 ms for 50 windows on a supported Apple Silicon Mac, excluding unresponsive third-party apps.
- P0: The menu-bar process should remain responsive during restore, AI, and display reconciliation.
- P0: Idle CPU should be negligible, with no continuous screen capture or high-frequency polling.
- P1: The Action Wheel should appear within 100 ms of its trigger.

### Reliability

- No controlled window may remain permanently off-screen after app quit, crash recovery, permission revocation, or Factory Reset.
- Layout operations must be idempotent where possible and guarded against stale accessibility references.
- Recovery, workspace load, and AI apply must use transaction boundaries with a pre-operation snapshot.
- Third-party app refusal or non-standard windows must produce partial-success reporting rather than silent loss.

### Accessibility

- All configuration and core actions are keyboard reachable.
- VoiceOver labels every Stage card, tab, pane control, wheel action alternative, rule, and status item.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, and system accent/color settings.
- Do not rely on color alone for active Stage, selected tab, errors, or Pro state.

### Compatibility

- Maintain an app-compatibility test set covering Safari, Chrome, Firefox, Finder, Terminal, Ghostty, Xcode, VS Code/Electron, Slack, Preview, and common settings/dialog window patterns.
- Detect and mitigate accessibility behaviors that animate window movement when safe to do so.
- Maintain a curated default secondary-window and floating-window exception set.

## 11. Privacy and security requirements

- All window management and recovery state remains local.
- API keys live in Keychain and are never included in logs or backups.
- AI disclosure lists the exact metadata classes sent and distinguishes direct-to-provider, local, and managed-service paths.
- AI responses are treated as untrusted plans and validated against allowed operations, existing window identities, Stage limits, and display constraints.
- Custom commands require a deliberate trust decision, run without shell profiles, and never inherit hidden application secrets beyond the normal user process environment.
- Backups are schema validated before applying and cannot inject executable Custom Actions.
- License verification failure preserves data and restores Free behavior without hiding windows.
- Diagnostic exports redact tokens, keys, document paths where feasible, URLs beyond the minimum needed, and command text/output.

## 12. Packaging and monetization

Recommended packaging follows the reference product's value ladder while leaving exact prices to business validation.

| Capability | Free | Pro lifetime | Managed AI subscription |
|---|---:|---:|---:|
| Named Stages | 3 | 9 | 9 |
| Freeform mode and 16 snap zones | Yes | Yes | Yes |
| Stage Strip, Action Wheel, shortcuts | Yes | Yes | Yes |
| Multi-monitor support | Yes | Yes | Yes |
| Automatic Workspace Continuity | Yes | Yes | Yes |
| Portable settings backup | Yes | Yes | Yes |
| Tabbed Tiling and presets | No | Yes | Yes |
| Saved Workspaces | No | Yes | Yes |
| App Routing and Pinned Displays | No | Yes | Yes |
| AI Organizer with own key/local model | No | Yes | Yes |
| Managed AI credits | No | No | Yes |
| Custom Actions | No | Experimental | Experimental |

Commercial requirements:

- A trial or preview must never create a data hostage situation. Pro-only state remains stored and becomes usable again after upgrade.
- Device activation limits are visible before purchase and manageable from an account portal.
- A fixed offline verification grace period supports travel and short outages.
- Managed AI usage shows credits consumed, credits remaining, reset date, and the unit definition before subscription.

## 13. Success metrics

### Activation

- At least 70% of users who grant Accessibility create or accept at least two Stages in the first session.
- At least 60% successfully switch Stage and move one window during onboarding.
- Permission-to-first-success median under three minutes.

### Engagement

- Weekly active users switch Stages on at least three days per week.
- Median active user has at least three Stages and uses two control surfaces.
- At least 30% of multi-monitor users successfully complete a dock/undock recovery within 30 days.

### Reliability guardrails

- Fewer than 0.1% of Stage switches require Rescue Windows.
- Fewer than 0.5% of recovery transactions end in an unexplained partial state.
- Crash-free session rate above 99.8%.
- Zero known cases where uninstall/permission revocation leaves windows irrecoverably inaccessible.

### Commercial

- Track Free-to-trial, trial-to-Pro, and Pro-to-managed-AI conversion separately.
- Track whether paywall encounters follow demonstrated value rather than blocking onboarding.
- AI plan apply rate, refinement rate, undo rate, provider error rate, and managed-credit exhaustion are core quality signals.

## 14. Telemetry events

Telemetry is opt-in or privacy-preserving and never includes window titles, paths, URLs, app document contents, API keys, command text, or AI prompt bodies.

Suggested events:

- onboarding_started/completed/abandoned step
- accessibility_granted/revoked
- stage_created/switched/reordered/deleted/merged
- window_sent_to_stage and rescue_windows_invoked
- window_mode_changed with anonymous mode and display count
- layout_preset_applied and layout_mutation_undone
- checkpoint_restore_started/completed/partial/failed reason class
- display_disconnected/reconnected and restore_choice
- workspace_saved/load_started/load_completed/load_partial
- route_rule_matched/failed reason class
- ai_plan_requested/received/refined/applied/undone with provider category only
- shortcut_conflict_detected/resolved
- pro_trial_started/expired and paywall_surface

## 15. Delivery plan

### Phase 0 — Technical foundations

- Accessibility discovery and window identity prototype.
- Safe hide/show/restore strategy with Rescue Windows.
- Stable display fingerprinting and topology state machine.
- Crash-safe local persistence and migration framework.
- Compatibility harness for representative native, browser, and Electron apps.

Exit criterion: no-window-loss prototype across restart, permission revocation, and basic display disconnect tests.

### Phase 1 — Core free product

- Onboarding and permissions.
- Up to three named Stages across multiple displays.
- Stage switching, move-window commands, Stage Strip, Freeform mode, 16 snap zones.
- Rebindable shortcuts and basic menu-bar controls.
- Automatic Workspace Continuity and Rescue Windows.
- Portable settings backup and diagnostics.

Exit criterion: a user can install, organize three contexts, switch reliably, dock/undock, restart, and recover without manual repair.

### Phase 2 — Pro workspace product

- Nine Stages.
- Tabbed Tiling, pane/tab manipulation, native-tab compatibility, appearance controls, and presets.
- Saved Workspaces with preview, missing-display mapping, and optional Clean Load.
- App Routing, window behavior rules, app exceptions, and Pinned Displays.
- License, trial, daily preview, device management, and entitlement degradation.

Exit criterion: the reliability guardrails are met across the compatibility matrix and three-display test topologies.

### Phase 3 — AI Organizer

- Structured workspace snapshot and plan schema.
- AI panel, mention system, review/refine/apply/undo, and Recipes.
- BYOK providers, Keychain storage, model discovery, local endpoints, and Test Connection.
- Managed AI service, credits, billing, and privacy disclosures.

Exit criterion: every applied AI plan is validated, previewed, transactional, and reversible; no prompt/provider failure moves a window.

### Phase 4 — Advanced controls

- Fully customizable Action Wheel and custom submenus.
- Custom Actions with trust policy and Terminal handoff.
- Expanded accessibility, appearance, and power-user diagnostics.

## 16. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Accessibility API inconsistency across apps | Missing/stale windows and unreliable layouts | Compatibility matrix, per-app fallbacks, partial-success reporting, Rescue Windows |
| Off-screen parking leaks or traps windows | Visual defects or lost-window perception | Geometry safety calculation, global fallback, restore-on-exit/revocation, watchdog |
| Display identities collide or change | Windows restore to the wrong monitor | Composite hardware fingerprint, confidence scoring, user remapping, non-destructive preview |
| Native tabs and Electron lifecycle differ | Duplicate or stale tabs | Dedicated identity adapters and app-class regression tests |
| Dense feature model overwhelms new users | Low activation and misconfiguration | Progressive onboarding, good defaults, contextual explanations, search, staged disclosure |
| AI shares sensitive metadata | Privacy or compliance breach | Explicit disclosure, redaction controls, local/BYOK choices, no contents/screenshots/keystrokes |
| AI returns invalid/destructive actions | Workspace disruption | Strict plan schema, allowlist validation, preview, transactional apply, one-step undo |
| Command actions enable harmful automation | Security and trust loss | Experimental label, no profiles/stdin, confirmation invalidation, local-only storage, no backup transfer |
| Trial expiry disables active layouts | Perceived data loss | Preserve state, downgrade behavior safely, show restore/upgrade choices |
| macOS changes private behavior | Breakage after OS updates | Public APIs only, beta OS test program, stable/beta app channels, feature flags |

## 17. Release acceptance criteria

The first public release is not ready unless all of the following are true:

- A clean install completes onboarding on supported Intel and Apple Silicon Macs.
- Permission denial, later grant, and live revocation are recoverable.
- Stage switching and window sending pass with 1, 2, and 3 displays and at least 50 mixed-app windows.
- Restart, wake, dock, undock, disconnect, and reconnect tests preserve usability and recoverable state.
- Quitting or crashing Tatami does not leave controlled windows inaccessible.
- Every data-destructive action has confirmation or undo appropriate to its impact.
- Free/Pro entitlement changes preserve all user-created data.
- Settings import is atomic and rejects malformed/executable content.
- VoiceOver and keyboard-only flows cover onboarding, Stage management, recovery decisions, and Settings.
- Privacy review verifies local-state boundaries, Keychain use, telemetry exclusions, and AI disclosure.

## 18. Open product decisions

These choices require stakeholder validation before engineering estimates are final:

1. Should Tatami keep the reference product's nine-Stage ceiling or offer unlimited named Stages with only the first nine directly addressable?
2. Should Pinned Display be the user-facing term, or should it be framed as an “Always Visible Display” for clarity?
3. Is a lifetime Pro license the preferred model, or should the non-AI product use paid major upgrades?
4. Should managed AI be included in a subscription that also unlocks Pro, or sold only as an add-on to a lifetime license?
5. Should users be able to redact or exclude individual metadata fields before an AI request?
6. Is cloud sync of settings or Saved Workspaces strategically important, or should local export remain the only portability path?
7. Should Custom Actions ship in the main app, behind an Advanced switch, or as a separately installed helper?

## 19. Research sources

Primary product sources reviewed:

- [BetterStage documentation index](https://betterstage.app/docs)
- [BetterStage how-to dictionary](https://betterstage.app/how-to)
- [Getting Started](https://betterstage.app/docs/getting-started)
- [Stages](https://betterstage.app/docs/stages)
- [Workspaces & Continuity](https://betterstage.app/docs/workspaces)
- [Stages Bar](https://betterstage.app/docs/stages-bar)
- [Window Management](https://betterstage.app/docs/window-management)
- [Window Modes](https://betterstage.app/docs/window-modes)
- [TabStack](https://betterstage.app/docs/tabstack)
- [Layout Presets](https://betterstage.app/docs/layout-presets)
- [Snap Zones](https://betterstage.app/docs/snap-zones)
- [Snap Wheel](https://betterstage.app/docs/snap-wheel)
- [Custom Actions](https://betterstage.app/docs/custom-actions)
- [AI Staging](https://betterstage.app/docs/ai-staging)
- [AI Staging Providers](https://betterstage.app/docs/ai-staging-providers)
- [Shortcuts](https://betterstage.app/docs/keyboard-shortcuts)
- [Monitor Management](https://betterstage.app/docs/monitor-management)
- [Settings Reference](https://betterstage.app/docs/settings-reference)
- [Settings Backup](https://betterstage.app/docs/settings-backup)
- [License Keys](https://betterstage.app/docs/license-keys)
- [Troubleshooting](https://betterstage.app/docs/troubleshooting)
- [Features and positioning](https://betterstage.app/)
- [Pricing and packaging](https://betterstage.app/pricing)
- [FAQ](https://betterstage.app/faq)

### Evidence note

Feature behavior, plan boundaries, platform requirements, and privacy claims in this PRD are derived from the public sources above. Tatami naming, prioritization, performance targets, telemetry, data model, phased delivery, success metrics, risks, and release criteria are product recommendations inferred from that behavior rather than claims made by BetterStage.
