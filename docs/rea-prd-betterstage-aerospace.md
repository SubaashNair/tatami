# Reverse-engineering PRD: BetterStage 2.2.1 and AeroSpace 0.21.3

Produced 2026-10-12 with REA (github.com/morluto/rea, rea@6.4.0) run against the installed BetterStage.app and the official AeroSpace v0.21.3-Beta release, cross-checked with AeroSpace's public source. This document describes behaviour and architecture so Tatami can make informed product decisions. It does not copy code, assets, or copy text from either product.

## 1. Executive summary

| | BetterStage | AeroSpace |
|---|---|---|
| One line | Closed-source, commercial "Stages" workspace manager with snap, tabbed tiling and AI organizing | Open-source, keyboard-driven i3-style tiling window manager with emulated workspaces |
| Version analysed | 2.2.1 (build 2.2.1900), signed 2026-10-06 | 0.21.3-Beta, released 2026-07-16 |
| Primary mental model | Stage = a named group of windows spanning all monitors; instant switch | Workspace = a tiling tree per monitor; CLI-addressable, scriptable |
| Control style | Menu bar, Stages Bar overlay, Snap Wheel, trackpad gestures, shortcuts, AI | Config file plus `aerospace` CLI, modal key bindings |
| Window placement | Three per-monitor modes: macOS Native, TabStack (pane tree with tabs), legacy Bento Box | Always tiling tree (h/v tiles and accordion) plus floating |
| Hiding strategy | Windows parked off screen with a stash journal and watchdog; experimental SkyLight Space bridge | Windows moved to a corner of the screen (emulated workspaces); no private Spaces API required |
| Business model | Freemium: Free (3 Stages), Pro (9 Stages, window modes, ⌘Tab switcher), lifetime, annual, AI subscription | Free open source, Homebrew distribution |
| Min macOS | 14.0 | 13.0 |
| Private API use | SkyLight (SLS/CGS), MultitouchSupport, symbolic hotkey control | `_AXUIElementGetWindow` only |

The three findings that matter most for Tatami:

1. The installed BetterStage (2.2.1) is ahead of the docs-based parity roadmap, which was written against 2.0.5. The binary reveals shipped features the roadmap does not list: a ⌘Tab window switcher, saved Workspaces that include macOS Spaces, pinned displays, shared windows, a hosted plus bring-your-own-key AI staging stack with Recipes, trackpad gestures from 2 to 5 fingers, Quick Look preview handling, and a crash-safe "Workspace Continuity" recovery layer (section 4.8).
2. BetterStage treats window hiding as its hardest reliability problem. A large share of its roughly 230 named types are recovery, journal, quarantine, watchdog, lease and authority objects. Tatami's M1 journal and watchdog direction matches, and this is where the reference invests most.
3. AeroSpace shows the opposite trade: refuse private Spaces APIs entirely, keep the model small, and expose everything through a CLI and one text config. It is the better reference for scriptability and for a deterministic layout tree; BetterStage is the better reference for discoverable UI.

## 2. Method and evidence quality

### 2.1 What was run

REA was installed locally (`npm install --prefix .context/reabin rea-agents`) and run through its CLI. No analysis provider was available (`rea doctor` reports Hopper, Ghidra and IDA all missing), so the native decompiler workflows (`decompile`, `trace`, `function`, `search`) were not usable. Everything below comes from REA's execution-free static commands plus standard macOS tooling on the same artifacts.

| REA command | Target | What it produced |
|---|---|---|
| `doctor` | host | Provider readiness: Node 24.13 ok; Hopper, Ghidra, IDA missing |
| `inspect-plist` | both `.app` bundles | Bundle identity, min OS, URL scheme, usage strings, Sparkle feed |
| `inspect-signature` | both bundles | Signing identity, team, hardened runtime, entitlements |
| `inspect-macho` | BetterStage, AeroSpace, `aerospace` CLI | Linked frameworks, 2,720 / 1,913 imported symbols, segments, build tool versions |
| `inspect-artifact` | both bundles | Bundle anatomy and file inventory |

Supplementary, non-REA evidence: `strings` on the three executables (Swift type names, private framework paths, config and socket paths), BetterStage's shipped `en.lproj/Localizable.strings` (1,256 user-facing strings), its `ThirdPartyNotices.txt`, and for AeroSpace the cloned source, manpages and `default-config.toml`.

### 2.2 Confidence labels used in this document

| Label | Meaning |
|---|---|
| **Observed** | Read directly from a shipped file or REA output (plist, entitlements, import table, string table) |
| **Inferred** | Derived from names or strings; the behaviour was not executed. Type names such as `WindowStashWatchdog` imply a purpose but not its exact algorithm |
| **Source-confirmed** | AeroSpace only: confirmed in its public repository |

### 2.3 Limits

- No decompilation, so BetterStage algorithms (snap maths, tile layout, matching heuristics) are unknown. Only their existence and inputs are known.
- BetterStage was not run under a debugger or instrumented. Runtime behaviour such as exact latency was not measured.
- BetterStage's hosted AI and licensing server behaviour is unknown beyond client strings. No network traffic was captured.
- Strings can include dead or flagged-off features (the Bento Box "legacy" mode is an example of a feature still present but demoted).
- Legal posture: the reverse-engineering target is a commercial app. Findings are used only to specify Tatami's own behaviour. Do not reuse BetterStage strings, icons, symbol names, or preset artwork. Review BetterStage's licence terms before publishing derived material.

## 3. Evidence summary shared by both apps

Both are Swift, AppKit plus SwiftUI, menu-bar agents (`LSUIElement = true`), non-sandboxed, and both depend on the Accessibility API as their core control surface.

| Capability | BetterStage evidence | AeroSpace evidence |
|---|---|---|
| Window enumeration and control | `AXUIElementCopyAttributeValue`, `SetAttributeValue`, `PerformAction`, `CreateApplication`, `CGWindowListCopyWindowInfo` | Same AX set plus private `_AXUIElementGetWindow` to map AX elements to window IDs |
| Event-driven tracking | `AXObserverCreate`, `AddNotification`, run-loop source; `NSWorkspace` launch, terminate, activate, hide, active-Space and sleep/wake notifications | `AXObserver*`, `NSWorkspace` launch, terminate, activate, hide, unhide, active-Space notifications |
| Global input | `CGEventTapCreate` (keyboard and pointer taps), Carbon `RegisterEventHotKey`, `NSEvent`, private MultitouchSupport for raw trackpad gestures | Carbon `RegisterEventHotKey`, `CGEventCreateMouseEvent`/`CGEventPost` for mouse synthesis; no event tap |
| Display identity | `CGDisplayCreateUUIDFromDisplayID`, vendor, model, serial, rotation, mirror, built-in | `NSScreen` based; no UUID or serial imports |
| Screen content | `ScreenCaptureKit` (SCShareableContent, SCContentFilter, SCStreamConfiguration), `CGPreflightScreenCaptureAccess` | None |
| Frame pacing | `CVDisplayLink` for animation | None observed |
| Secrets and licence | `SecItem*` (Keychain), CryptoKit, LocalAuthentication, `SMAppService` | `SMAppService` (launch at login) only |
| Automation | `NSAppleScript`, `posix_spawn` with file actions and process groups | None observed in the app binary |
| Updates | Sparkle 2.8.1 (EdDSA public key, daily check, feed at update.betterstage.app) | Homebrew cask (no in-app updater observed) |
| Local IPC | Custom URL scheme `betterstage://` | `NWListener` / `NWConnection` server; socket under `/tmp/bobko.aerospace…` shared with the CLI |
| Signing | Developer ID Application, team 399UXJ8NC8, hardened runtime, Apple Events entitlement | Self-signed certificate "aerospace-codesign-certificate", no hardened runtime, `get-task-allow` true |
| Binary | Universal x86_64 and arm64, 81 MB executable, SDK 14.0, Sparkle embedded | Universal, about 3.3 MB of `__TEXT`, SDK 26.5 (Xcode 26.5), separate `aerospace` CLI binary |
| Localization | 20 `.lproj` folders (ar, da, de, en, es, fr, he, it, ja, ko, nb, nl, pl, pt, ru, sv, uk, zh-Hans, zh-Hant) | English only |

---

## 4. Product A: BetterStage 2.2.1

### 4.1 Problem and positioning

Observed positioning copy, paraphrased: keep groups of windows together, switch tasks instantly, and return to where you left off, across every monitor, while keeping native macOS windows. Two promises recur in the UI text: "instant context switching" and "native macOS windowing, enhanced". It targets people who run many apps across several projects and find macOS Spaces and Mission Control too slow and too coarse.

### 4.2 Target users (inferred from UI vocabulary)

| Persona | Evidence | Job to be done |
|---|---|---|
| Multi-project professional | Stages, Workspaces, "Work" and "Personal" example workspaces, chat apps pinned to a monitor | Swap a whole context of 10 to 30 windows in one keystroke |
| Keyboard-first power user | 9 numbered Stage shortcuts, Option and Control+Option families, custom shortcut recorder, keyboard-layout chooser (ANSI vs others) | Drive everything without the mouse; avoid typing conflicts |
| Visual organizer | Stages Bar with previews, Snap Wheel, drag-to-pane, presets | Arrange windows by direct manipulation |
| AI-curious user | AI Staging panel, Recipes, 20 or more model providers | Let a model sort a messy desktop into Stages |
| Multi-Mac owner | Lifetime licence for 3 Macs, device list, export and import of settings | Keep the same setup on laptop and desktop |

### 4.3 Product model and terminology (all observed in the string table)

| Term | Meaning |
|---|---|
| **Stage** | Named group of windows spanning all displays. Up to 9. Only one is active; others are hidden |
| **Workspace** | A saved, reusable setup of Stages, displays, layouts and app windows. Can be saved, previewed, renamed, deleted, loaded (merge or "Clean Load"), exported |
| **Saved Space** | A macOS Desktop recorded inside a Workspace. Loading recreates missing Desktops via Mission Control automation |
| **Window Mode** | Per-monitor behaviour: macOS Native (freeform plus snap), TabStack (panes with tab groups), Bento Box (legacy auto-grid, hidden unless enabled) |
| **Pane / Tab** | TabStack units. A pane holds one or more windows presented as tabs |
| **Stages Bar** | Overlay of Stage cards with previews, opened by shortcut or by pushing the pointer to the top edge |
| **Snap Wheel** | Radial menu at the pointer, with inner and outer rings, submenus and custom slots |
| **Recipe** | Saved natural-language instruction that steers AI Staging |
| **Routing Rule / App Routing** | Rules that send matching new windows to a Stage |
| **Window Behavior Rule** | Per-window or per-app policy: Automatic, Manage in Layout, Keep Floating |
| **Custom Action** | User-defined action: open app, open file, run command, run Shortcut, submenus. Trust prompts on change |
| **Pinned Display** | A display that stays visible across Stage switches |
| **Rescue** | Recovery command that reveals every hidden window, merges Stages and resets modes |

### 4.4 Functional requirements (reconstructed)

Priority: **P0** core to the product thesis, **P1** expected by paying users, **P2** differentiator or late addition. All rows are Observed unless marked Inferred.

#### 4.4.1 Stages and navigation

| ID | Requirement | Pri |
|---|---|---|
| BS-STG-01 | Up to 9 named Stages across all displays; Free plan limited to 3, extra Stages locked (not deleted) when Pro lapses | P0 |
| BS-STG-02 | Switch to Stage N by number, previous and next, cycle, and via menu; "Switch Stage" submenus list existing Stages automatically | P0 |
| BS-STG-03 | Send a window to Stage N, previous or next; "Send Window" fan menu; move overflow windows to the next Stage when a layout is full | P0 |
| BS-STG-04 | Create, rename, reorder, close Stage; "Merge" all Stages | P0 |
| BS-STG-05 | Follow focus: when a window becomes active, switch to its owning Stage; also when App Routing places a new window elsewhere | P1 |
| BS-STG-06 | Show a window in multiple Stages (shared windows); sharing can end or be refused with a reason | P2 |
| BS-STG-07 | Minimized windows appear as "Minimized" entries and are restored when chosen | P1 |
| BS-STG-08 | Switch indicator toast after a switch; reveal-delay setting for the Stages Bar | P1 |
| BS-STG-09 | Stages vs macOS Spaces choice: either one Desktop per monitor with Stages, or multiple Spaces per Stage each with its own layout. UI recommends picking one | P1 |

#### 4.4.2 Window modes, snap and tiling

| ID | Requirement | Pri |
|---|---|---|
| BS-WIN-01 | Per-monitor Window Mode, cycled by shortcut or menu: macOS Native, TabStack, (legacy) Bento Box | P0 |
| BS-WIN-02 | macOS Native: freeform windows, snap zones (halves, thirds, two-thirds, quarters, centre), snap layouts, Retile, Re-stack (cascade), Full Screen grow | P0 |
| BS-WIN-03 | Snap geometry honours per-side screen padding and gaps, with per-display overrides | P1 |
| BS-WIN-04 | TabStack: pane tree per monitor; split horizontal, vertical, above, below; join as tabs; swap panes (Option-swap); zoom pane and restore; rebalance; clean up empty panes; reflow as grid | P0 |
| BS-WIN-05 | Drag overlay for TabStack: blue split zones, drop-to-swap, divider insertion, ghost frames for live resize that can be turned off | P1 |
| BS-WIN-06 | Tab bar configuration: edge (top, vertical rail), icon-only vs icon plus title, height and width, auto-hide with an edge marker, active and inactive colours, glass opacity and tint | P1 |
| BS-WIN-07 | New-window placement: Automatic, Active pane, Adjacent pane, Own pane; max tiled windows per display (up to 12) | P1 |
| BS-WIN-08 | Window behaviour per window or by rule: Automatic, Manage in Layout, Keep Floating; "Exclude App" from auto-tiling; Raise Floats ("bring floating windows to front") | P1 |
| BS-WIN-09 | Preset layouts (built in, read-only) and user-saved TabStack presets; AI can pick a preset; first-time prompt when switching to TabStack | P1 |
| BS-WIN-10 | Launch app here, Quit app and Relaunch app from a tab or empty pane; drag-and-launch card for empty panes | P2 |
| BS-WIN-11 | Layout undo | P1 |
| BS-WIN-12 | Pop-up apps and Quick Look previews: included in layout or left floating by setting | P2 |

#### 4.4.3 Input

| ID | Requirement | Pri |
|---|---|---|
| BS-INP-01 | Global shortcuts via Carbon hotkeys plus a keyboard event tap on its own thread; shortcut recorder with conflict detection, reserved keys (Escape, Delete), and two preset families (Option-based for ANSI layouts, Control-based for typing-friendly) | P0 |
| BS-INP-02 | Snap Wheel triggers: middle click, modifier hold, custom combos, trackpad gestures (swipe, tap, click, pinch with 2 to 5 fingers) read from private MultitouchSupport; hold vs toggle; title-bar only option; open delay | P1 |
| BS-INP-03 | Pinch gestures can be unavailable because macOS claims them; the UI says so and degrades | P2 |
| BS-INP-04 | Disable conflicting macOS symbolic hotkeys when needed (symbolic hotkey guard) | P2 |
| BS-INP-05 | Option plus scroll to switch Stage (present in the 2.0.x docs; not independently re-verified in the binary) | P2 |

#### 4.4.4 ⌘Tab switcher (new since 2.0.5)

| ID | Requirement | Pri |
|---|---|---|
| BS-SWT-01 | Replaces macOS ⌘Tab with a searchable switcher over every window in every Stage; "Keep macOS ⌘Tab" is an option. Pro feature that activates automatically when Pro is active | P1 |
| BS-SWT-02 | Optional live thumbnails through ScreenCaptureKit; without Screen Recording permission it shows app icons. A permission-guide flow opens System Settings and positions an overlay to drag BetterStage into the list | P1 |
| BS-SWT-03 | After a switch, briefly outline the focused window and pulse its TabStack tab | P2 |
| BS-SWT-04 | Include minimized windows toggle; type-to-search windows, apps and Stages | P1 |

#### 4.4.5 Workspaces and recovery (the reliability core)

| ID | Requirement | Pri |
|---|---|---|
| BS-WSP-01 | Save current Stages, layouts and window inventory as a Workspace; load into current or replace; "Clean Load" quits non-member apps first, never force-quits, and stops if an app stays open | P1 |
| BS-WSP-02 | Option to open missing apps and create missing windows on load, otherwise restore only existing windows | P1 |
| BS-WSP-03 | Workspace Continuity: automatic checkpoints that survive crashes, sleep and display changes; repairs can be disabled; unreadable checkpoints are preserved untouched; a newer-version Workspace file is opened read-only | P0 |
| BS-WSP-04 | Display disconnect: windows move to a temporary Stage, the display layout is remembered until it returns, "Display added: existing windows left in place" | P0 |
| BS-WSP-05 | Wake-restore undo, saved-setup undo transactions, and a "windows rescued" flow | P1 |
| BS-WSP-06 | Hiding other Stages' windows can be paused while macOS Spaces cannot be read; a banner explains this and retries automatically | P0 |
| BS-WSP-07 | Factory reset as a durable transaction retried on next launch if interrupted | P2 |
| BS-WSP-08 | Settings backup: export and import preferences, App Exceptions, window rules, display settings, shortcuts, AI Recipes and TabStack layouts; credentials, Stages and Custom Actions stay local | P1 |

#### 4.4.6 Routing and window rules

| ID | Requirement | Pri |
|---|---|---|
| BS-RTE-01 | App Routing: rules send matching new windows to a Stage; conflicts and stale edits are detected ("rule changed elsewhere") | P1 |
| BS-RTE-02 | Window rule editor matches by app, window role and control structure, or an advanced title condition (contains, exactly); live preview of what matches; unsafe or untitled windows cannot get title exclusions | P1 |
| BS-RTE-03 | App groups for reuse in rules; "installed application catalog" picker with search | P2 |

#### 4.4.7 AI Staging

| ID | Requirement | Pri |
|---|---|---|
| BS-AI-01 | "Ask AI to sort open windows into Stages": a chat panel produces a Stage plan with preview, refine, grid editor, apply and undo; every planned Stage must have a name and at least one window | P1 |
| BS-AI-02 | Two transports: hosted BetterStage AI (usage tracked, rate limited, can be "temporarily unavailable") and bring-your-own-key | P1 |
| BS-AI-03 | BYO providers observed: OpenAI-compatible custom endpoint, Azure OpenAI, Google Gemini, OpenRouter, Groq, DeepSeek, Moonshot (Kimi), Zhipu (GLM), Alibaba Qwen, Xiaomi MiMo, MiniMax, StepFun, SiliconFlow, Tencent Hunyuan, ByteDance Doubao, Novita, Together, NVIDIA NIM, Hugging Face, Ollama and LM Studio (local). Model list fetched live with a curated fallback | P1 |
| BS-AI-04 | Recipes: saved natural-language rules with a live preview of exactly what the model sees; wizard-built or hand-written; optional per request; `@` to reference windows; custom instructions | P2 |
| BS-AI-05 | Keys stored in Keychain; if save fails the key lives only until quit | P0 |
| BS-AI-06 | Workspace too large for one request: ask the user to arrange fewer windows or a single Stage | P2 |

#### 4.4.8 Custom Actions

| ID | Requirement | Pri |
|---|---|---|
| BS-ACT-01 | Action types: open app, open file, run command (background or visible in Terminal via Apple Events), run Shortcuts action, custom submenus. Up to 256 saved actions | P1 |
| BS-ACT-02 | Commands run with the user's permissions, without shell startup files, stdin or a terminal; command text and output are not logged; timeout and cancel states exist | P0 |
| BS-ACT-03 | Trust prompt when an action changed or arrived from another version; assignments on the wheel are disabled and must be reassigned after a schema change | P1 |

#### 4.4.9 Onboarding, licence and settings

| ID | Requirement | Pri |
|---|---|---|
| BS-ONB-01 | Post-start onboarding: choose window mode, keyboard layout, shortcut family, Stage setup wizard ("where do your chat apps belong"), optional previews, Accessibility permission guide that opens System Settings and overlays a drag target | P0 |
| BS-LIC-01 | Plans: Free; Pro trial with day countdown and a short Pro preview; lifetime (1 Mac or 3 Macs); annual and monthly subscriptions; AI add-on monthly or annual; giveaway keys; refunded keys deactivate | P1 |
| BS-LIC-02 | Device activation with device-limit handling, offline lease with deadline scheduler, "Connect once to finish securing your licence", clock-skew detection, fail-closed marker; Free mode starts safely if verification fails | P1 |
| BS-SET-01 | Menu bar item with indicator and hover tooltip; startup at login; update channel (Stable) and Sparkle checks; Discord community link; 20 UI languages | P1 |

### 4.5 Core flows

1. **First run.** Launch, grant Accessibility (guided overlay), pick Window Mode and keyboard layout, choose shortcut family, optionally enable previews (Screen Recording), seed Stages from running windows or ask AI, then see the Stages Bar tip.
2. **Switch context.** Press a Stage shortcut or touch the top edge, pick a card; windows of other Stages are hidden, the target Stage's windows are shown with their layout.
3. **Tile a display.** Cycle the monitor to TabStack, accept the default layout prompt, drag windows onto split zones, join as tabs, resize dividers with ghost frames.
4. **Dock and undock.** Disconnect a display; its windows move to a temporary Stage; reconnect and the layout is restored.
5. **AI arrange.** Open AI Staging, optionally pick a Recipe, review the proposed plan, refine in chat, apply, undo if needed.
6. **Recover.** If hiding fails or windows are lost, Rescue reveals all hidden windows and resets modes.

### 4.6 Architecture (Inferred from about 230 Swift type names plus the import table)

The module is a single app target named `BetterStage` plus one SwiftPM resource bundle. Type families:

| Layer | Representative types | What it implies |
|---|---|---|
| Window tracking | `WindowTracker`, `WindowLifecycle`, `WindowLifecycleRegistry`, `TrackedWindowIdentityAuthority`, `AXNotificationIngress`, `AXObserverLifecycleAuthority`, `AXObserverRunLoopBinding`, `AppAXThread`, `AppAXThreadRegistry`, `AXElementCaptureAuthority` | One AX thread per target app, observers bound to its run loop, a stable window identity layer on top of volatile AX elements |
| Stage state | `Stage`, `StageManager`, `StageStore`, `StageStoreJournal`, `WindowStageMapMutationAuthority`, `StageExcludedApps` | Journaled store; mutation goes through an "authority" that serialises writes |
| Hiding | `WindowStashJournalLease`, `WindowStashWatchdog`, `WindowSpaceStash`, `WindowVisibility`, `OffscreenDiscoveryQuarantineAuthority`, `OffscreenDiscoveryFocusProofCompletionGate`, `DesktopExposureMonitor`, `NativeSpaceCoordinator`, `NativeSpaceWindowAuthority`, `WindowSpaceBridge` | Off-screen parking with a lease, watchdog and quarantine; optional SkyLight Space bridge for true Spaces moves |
| Layout | `TileEngine`, `TileTreeRoot`, `SplitNode`, `WindowLeaf`, `TileMetrics`, `TileAnimator`, `SnapEngine`, `LayoutUndoStack`, `WindowLayoutPlacementValidity`, `DeferredWindowMutationAuthority`, `BoundedWindowWriteLockPool`, `AnimationWindowWriter` | A binary split tree (names say BSP); animated writes go through a mailbox; per-window write locks are pooled |
| TabStack UI | `PresetPaneContainerView`, `PresetPaneTabStripView`, `PresetPaneTabIslandView`, `PresetPaneTabOverlay`, `BSPInsertionOverlay`, `BSPResizeGhostOverlay`, `PresetPaneDragGhostOverlay`, `TabbedLayoutPresetStore` | Overlay panels draw tab bars and drop targets above real windows; windows are not re-parented |
| Input | `ShortcutManager`, `HotkeyRouter`, `KeyboardEventTapThread`, `EventTapControlQueue`, `MultitouchDeviceWatcher`, `RawTrackpadGestureMonitor`, `SystemTrackpadGestureMonitor`, `TrackpadGestureRecognizer`, `TitleBarDragDetector`, `SymbolicHotKeyGuard`, `InputResponsivenessMonitor` | Dedicated tap thread, a responsiveness monitor to detect a stalled tap |
| Overlays | `StagesBarController`, `SnapWheelController`, `SnapWheelPanel`, `SwitcherController`, `SwitcherPanel`, `WindowHighlightOverlay`, `DisplayIdentifyOverlay`, `TileToast` | Non-activating panels |
| Continuity | `WorkspaceContinuityCoordinator`, `WorkspaceCheckpointStore`, `WorkspaceRestoreEngine`, `SavedSetupStore`, `SavedSetupLibrary`, `WakeRestoreUndoTransaction`, `PreSleepTransitionGate`, `DriftRepairScheduler`, `NativeDisplayReconnectSession`, `MonitorManager` | Pre-sleep gate, checkpoint after change, repair scheduler for drift |
| AI | `AIStagingManager`, `AIStagingChatSession`, `AIStagingActionApplier`, `BYOAIStagingTransport`, `HostedAIStagingTransport`, `RoutingAIStagingTransport`, `AIStagingPromptLibraryStore`, `ModelsDevCatalog`, `StagingUsageStore` | Transport abstraction; model catalogue sourced from a public models list |
| Actions and rules | `UserActionLibrary`, `UserActionRunner`, `UserActionExecutor`, `WindowBehaviorRules`, `WindowBehaviorRuleEditor`, `AppRoutingRuleStore`, `AppGroupStore` | Rule stores with editors |
| Licence | `EntitlementAuthorityCoordinator`, `EntitlementLeaseManager`, `EntitlementStorage`, `DeviceSigningIdentityProvider`, `DeviceLockClient`, `ProManager`, `ProPreview`, `FileFailClosedMarkerStore` | Signed device identity, lease with deadline, fail-closed marker |
| Platform | `PermissionsManager`, `AccessibilityPermissionFlowController`, `ScreenRecordingPermissionModel`, `UpdateManager`, `MenuBarManager`, `ActivationPolicyCoordinator` | Permission helper adapted from the MIT project PermissionFlow; SkyLight bridge adapted from the MIT project WindowKit (both credited in ThirdPartyNotices) |

The recurring design pattern is "Authority", "Gate", "Journal", "Lease", "Token" objects. These encode ordering and ownership rules for mutations that cross threads and survive crashes. That is the architectural signature of the product.

Private and sensitive APIs referenced (Observed in `strings`): SkyLight `SLSCopyManagedDisplaySpaces`, `SLSBridgedSpaceCreateOperation`, `SLSBridgedSpaceDestroyOperation`, `SLSBridgedMoveWindowsToManagedSpaceOperation`, `SLSBridgedSpaceAddWindowsAndRemoveFromSpacesOperation`, `SLSBridgedSpaceSetAbsoluteLevelOperation`, `SLSSetActiveMenuBarDisplayIdentifier`; CoreGraphics `CGSCopySpacesForWindows`, `CGSDisableUpdate`, `CGSReenableUpdate`, `CGSSetWindowAlpha`, `CGSSetSymbolicHotKeyEnabled`; and `MultitouchSupport.framework`. The notices call the SkyLight bridge "experimental". They are resolved at runtime (the framework paths appear as strings, not in the Mach-O import table), so the app still launches if a symbol disappears in a future macOS.

### 4.7 Non-functional requirements (derived)

| Area | Requirement | Evidence |
|---|---|---|
| Latency | Stage switch must feel instant; the reference avoids animation for switches and uses a display link only for tile animation | `CVDisplayLink` imports, "Instant Context Switching" copy; no measured number in the binary |
| Safety | Never force-quit apps; never destroy data on a failed load; preserve unreadable state | Multiple strings |
| Failure containment | Every hide failure has a visible banner and automatic retry; permission loss pauses management | Strings, `AccessibilityLossSignal` |
| Privacy | Screen Recording used only for previews; command text not logged; keys in Keychain | Strings, `SecItem*` imports |
| Compatibility | macOS 14+, universal binary | Info.plist, Mach-O |
| Internationalization | 20 languages, plural rules via `.stringsdict`, RTL languages (Arabic, Hebrew) shipped | Resources |
| Supportability | Settings export, factory reset, Discord community, "contact support" in unrecoverable-data messages | Strings |

### 4.8 What changed since the docs-based roadmap (2.0.5 to 2.2.1)

| New or changed in binary | Tatami status (per `docs/betterstage-parity.md`) | Suggested action |
|---|---|---|
| ⌘Tab switcher with search and previews (Pro) | Not listed | Candidate for M5; high daily-use value |
| Workspaces that include macOS Spaces; Mission Control Desktop creation | Basic saved arrangements only | Decide whether Tatami supports Spaces at all (section 6) |
| Pinned displays | Display rows partly done | Add as a per-display flag honoured on Stage switch |
| Shared windows (window in multiple Stages) | Marked missing | Keep deferred; adds identity complexity |
| Hosted AI plus 20-provider BYO; Recipes; chat refine; undo | Tatami has BYO providers and plan validation; Recipes listed as remaining | Add Recipes; stay BYO-first |
| Trackpad gestures with 2 to 5 fingers | Missing (needs private MultitouchSupport) | Defer; only with explicit risk acceptance |
| Window Behavior rules with live match preview | Rules exist | Add match preview to the editor |
| Bento Box demoted to "legacy"; TabStack is the primary tiling mode | Tatami has TabStack | Do not build Bento |
| Quick Look and pop-up app handling | Not listed | Add to window classification |
| Settings backup, factory reset transaction | Settings backup exists | Add resumable factory reset |
| Licence: lifetime 1 or 3 Macs, annual, AI add-on, trial preview | Intentionally out of scope for Tatami | Revisit when shipping |
| Workspace Continuity checkpoints with newer-version read-only protection | Partly in the M1 journal | Add a schema version guard and a "preserve unreadable" rule |

---

## 5. Product B: AeroSpace 0.21.3-Beta

Evidence for this section is Observed (REA on the release binaries and bundle) and Source-confirmed (public repository, manpages, `default-config.toml`, docs). Key figures were spot-checked against the files: 45 commands (46 manpage files including the overview), about 21,000 lines of Swift of which 5,705 are tests, 393 test functions.

### 5.1 Problem and positioning

"An i3-like tiling window manager for macOS." It is built for developers and keyboard-centric power users who want a deterministic window tree, fast workspace switching with no animation, a plain-text config they can keep in dotfiles, and a CLI that scripts everything. It deliberately ignores native macOS Spaces and never requires disabling SIP.

Stated values (README):

- Advanced users first, keyboard-centric, no GUI configuration ever (a status-menu icon is acceptable).
- Practical features only: no borders, transparency or animations.
- Avoid dark magic: the single private API is `_AXUIElementGetWindow`; everything else is public Accessibility.
- Maintainable and resistant to macOS updates.
- Breaking changes are allowed before 1.0, then semver-major only.

Stated non-values: playing nicely with native Spaces features, and "ricing" (only gaps and a few bar-integration callbacks).

### 5.2 Target users

| Persona | Evidence | Job to be done |
|---|---|---|
| i3 or sway refugee on macOS | i3 vocabulary (node, accordion, modes), i3-like default bindings | Same muscle memory on a Mac |
| Dotfiles-driven developer | TOML config in `~/.aerospace.toml` or XDG path, auto-reload, completions, manpages | Version-control the whole setup |
| Scripter or bar integrator | `subscribe` event stream, `--json`, `exec-on-workspace-change`, Sketchybar docs | Drive status bars and automations from window events |
| Multi-monitor desk user | Per-monitor gaps, force-assigned workspaces, `summon-workspace` | Predictable workspace-to-monitor mapping |

Non-target: users who want a GUI, animations, or Spaces integration.

### 5.3 Product model and terminology (Source-confirmed)

| Term | Meaning |
|---|---|
| **Node** | Any element of the tree. i3 calls the container "container"; AeroSpace's term for the generic thing is node |
| **Window** | The only leaf |
| **Container** | Non-leaf node with a layout (`tiles` or `accordion`) and orientation (`h` or `v`), giving `h_tiles`, `v_tiles`, `h_accordion`, `v_accordion` |
| **Workspace** | Named tiling tree plus floating, native-fullscreen and hidden-app containers. Created lazily by name, garbage collected when empty and not persistent |
| **Monitor** | Shows exactly one workspace at a time; two monitors cannot show the same workspace. Every workspace has an assigned monitor |
| **Mode** | Named set of key bindings (`main` is mandatory), like i3 binding modes. A service mode ships in the default config |
| **Callback** | Config-defined command run on events: window detected, focus changed, monitor changed, mode changed, workspace change |
| **Emulated workspace** | A workspace hidden by moving its windows to a screen corner, instead of using a native Space |

### 5.4 Functional requirements (reconstructed)

| ID | Requirement | Pri |
|---|---|---|
| AS-TRE-01 | One root tiling container per workspace; `tiles` and `accordion` layouts, horizontal and vertical orientation; accordion shows the most-recently-used window on top with configurable side padding (default 30) | P0 |
| AS-TRE-02 | New windows insert right after the most-recently-used window in its parent; otherwise into the root | P0 |
| AS-TRE-03 | Normalization on every refresh: flatten single-child containers; alternate orientation for nested containers; both on by default and individually switchable | P0 |
| AS-TRE-04 | Weights per child; `resize` (smart, width, height, relative or absolute) and `balance-sizes` | P0 |
| AS-TRE-05 | Floating windows live outside the tree; dialogs and popups float automatically using an Accessibility heuristic (no fullscreen button means dialog, except terminals); toggle with `layout floating tiling` | P0 |
| AS-TRE-06 | macOS-native states handled by reparenting: native fullscreen, minimized, hidden (cmd-h) apps, and popup pseudo-windows each get a container, and windows return to their previous kind when the state ends | P1 |
| AS-TRE-07 | AeroSpace-native `fullscreen` that exits when another tiling window gets focus | P1 |
| AS-WSP-01 | Emulated workspaces: inactive workspaces' windows are moved to a bottom corner of their monitor with a 1 px sliver left on screen; a corner-scoring heuristic avoids overlapping neighbouring monitors; on quit or detected crash all windows are restored | P0 |
| AS-WSP-02 | `workspace`, `workspace-back-and-forth`, `move-node-to-workspace`, `summon-workspace`; any-string workspace names; `persistent-workspaces` (config-version 2) | P0 |
| AS-MON-01 | Force-assign workspaces to monitors by `main`, `secondary`, 1-based index or regex on name; first match wins in an array | P1 |
| AS-MON-02 | `focus-monitor`, `move-node-to-monitor`, `move-workspace-to-monitor` (ignored for force-assigned workspaces), `move-mouse` helpers; per-monitor gaps | P1 |
| AS-CLI-01 | 45 commands grouped as: focus (3), move and rearrange (7), layout (4), workspaces (4), monitors (3), windows (2), query (7), modes, config and state (6), scripting (8), diagnostics (1) | P0 |
| AS-CLI-02 | Context targeting order: `--window-id`, then `--workspace`, then `AEROSPACE_WINDOW_ID`, then `AEROSPACE_WORKSPACE`, then current focus | P1 |
| AS-CLI-03 | Query commands share `--format` interpolation, `--count` and `--json` | P1 |
| AS-CLI-04 | `subscribe` streams JSON-lines events: focus-changed, focused-monitor-changed, focused-workspace-changed, mode-changed, window-detected, binding-triggered; current state sent on connect unless `--no-send-initial` | P1 |
| AS-CLI-05 | Shell-like grammar for bindings and callbacks: `;`, `&&`, `\|\|`, `\|` and parentheses | P1 |
| AS-CLI-06 | Shell completions (bash, fish, zsh) and manpages shipped for every command | P2 |
| AS-CFG-01 | TOML 1.1 config at `~/.aerospace.toml` or `${XDG_CONFIG_HOME:-~/.config}/aerospace/aerospace.toml`; both present is an error; bundled default config is the fallback; omitted keys use defaults | P0 |
| AS-CFG-02 | `auto-reload-config` through a file watcher with a 200 ms debounce; `reload-config` with `--dry-run` and `--warnings-as-errors` | P1 |
| AS-CFG-03 | Key binding syntax `mod-mod-key = 'command'` (cmd, alt, ctrl, shift), string or array of commands, per mode; QWERTY by default with dvorak and colemak presets and custom key-notation mapping | P0 |
| AS-CFG-04 | `on-window-detected` ordered rules with a shell `if` condition, a `run` command and `check-further-callbacks`; used to assign apps to workspaces or float them | P0 |
| AS-CFG-05 | Gaps: inner horizontal and vertical, outer left, right, top, bottom, each a constant or a per-monitor list with a default | P1 |
| AS-CFG-06 | `focus-follows-mouse`, `automatically-unhide-macos-hidden-apps`, `start-at-login`, `after-startup-command`, `exec` environment control | P2 |
| AS-IPC-01 | Client and server over a Unix-domain socket (`/tmp/bobko.aerospace-$USER.sock`) via Network.framework; handshake exchanges protocol version as UInt32 (currently 1); frames are `[UInt32 length][UTF-8 JSON]`; request `{args, stdin, windowId?, workspace?}`, response `{exitCode, stdout, stderr, serverVersionAndHash}`; protocol is documented as public | P0 |
| AS-IPC-02 | A disabled server rejects everything except `enable`; `aerospace -v` warns when client and server versions differ | P2 |
| AS-UI-01 | Menu-bar item only (no Dock icon): status text, enable toggle, reload, config open, sponsorship button | P1 |
| AS-DST-01 | Distribution through a Homebrew cask in the author's tap, plus manual zip; not notarized, so the cask strips the quarantine attribute | P1 |

### 5.5 Core flows

1. **Install and first run.** `brew install --cask nikitabobko/tap/aerospace`, grant Accessibility, start; the bundled default config provides i3-style bindings (alt plus h, j, k, l to focus, alt plus 1 to 9 for workspaces).
2. **Everyday use.** Windows auto-tile into the focused workspace; `alt-shift-<digit>` sends one elsewhere; `alt-tab` flips between two workspaces.
3. **Customize.** Edit TOML, save, auto-reload applies it; add an `on-window-detected` rule so a chat app always opens on workspace C.
4. **Script.** A shell script runs `aerospace list-windows --json`, or subscribes to events to update a status bar.
5. **Recover.** Quit the app; all windows are moved back on screen. After a hard crash, drag the 1 px sliver back.

### 5.6 Architecture (Source-confirmed, matches REA binary evidence)

SwiftPM package (tools 6.2, macOS 13+) with these targets:

| Target | Role | Swift LOC |
|---|---|---|
| `PrivateApi` | C header exposing `_AXUIElementGetWindow` | 28 |
| `Common` | Shared by client and server: command-argument parsing, models, socket protocol, help text | 4,218 |
| `AppBundle` | The server library: tree, layout, config, commands, shell, mouse, UI | 10,992 |
| `Cli` | Thin `aerospace` client | 226 |
| `AppBundleTests` | 393 tests with mock apps, windows and AX elements; about 120 real AX dump samples under `axDumps/` | 5,705 |

An Xcode project exists only because SwiftPM cannot produce an app bundle; it wraps `AppBundle`. Dependencies: TOMLDecoder, HotKey (Carbon hotkeys), swift-collections, ISSoundAdditions (volume command).

REA corroboration: the app links Network.framework (`NWListener`, `NWConnection`), AppKit, Carbon, CoreAudio, ServiceManagement, SwiftUI and Swift `_StringProcessing` (regex). It imports 1,913 symbols and exports 7,222. The CLI links only Foundation, AppKit and Network. Strings contain `.aerospace.toml`, `aerospace.toml` and `/tmp/bobko.aerospace`, matching the source.

Key mechanisms:

- **Observation.** One dedicated thread per target app, each with its own run loop, owns all Accessibility calls for that app. Per-app notifications: window created, focused window changed. Per-window: destroyed, miniaturized, deminiaturized, moved, resized. Global `NSWorkspace` notifications plus a global mouse-up monitor cover the unreliable window-destroyed notification. Window creation detection is delayed while the left button is down (tab tear-off apps).
- **Two session kinds.** A heavy refresh (triggered by any observer event) reads focus, normalizes the tree, polls apps and windows, registers new windows, handles fullscreen and minimized state, then lays out workspaces. It is cancellable; a new event supersedes it. A light session (commands, hotkeys, socket) cancels any in-flight heavy refresh, runs the command body, lays out, syncs native focus, then schedules a heavy refresh. Commands therefore always win.
- **Hiding.** Windows of inactive workspaces move to a monitor corner with a 1 px offset; pre-hide position is saved as proportions so floating windows return correctly. Order to limit flicker: unhide and lay out visible workspaces first, then hide the rest. Frame writes use size, then position, then size again, with Accessibility "enhanced user interface" animations disabled during writes.
- **Threading.** Main actor owns the model. AX objects are thread-confined by runtime guards. Latest-write-wins per-window frame jobs. Swift 6 strict concurrency; invariant violations crash deliberately (`die`).
- **Planned.** Rewrite to an immutable tree (fixes windows jumping to the focused workspace and enables native tabs); post-1.0 ideas are sticky windows and dynamic tiling.

### 5.7 Non-functional requirements (derived)

| Area | Requirement | Evidence |
|---|---|---|
| Latency | Workspace switch has no animation; commands pre-empt background refresh | Docs, session design |
| Robustness | Restore all windows on quit or crash detection | Docs, `setAxFrameForTermination` |
| Compatibility | Runtime macOS 13+; release builds need macOS 15+ and Xcode 26.6+; supports native fullscreen, minimized and hidden-app states | README, plist |
| Maintainability | Few private APIs; strict concurrency; tests with real AX dumps | Source |
| Extensibility | Public socket protocol; JSON output; event stream | Docs |
| Distribution | Self-signed, not notarized; server must be restarted after update | Signature, docs |
| Quality gate | CI on macOS 14, 15, 26 and the newest Xcode, daily cron; lint, format and generated-file checks in `test.sh` | Workflows |

### 5.8 Risks and limitations (as documented)

- 1 px sliver of hidden windows; monitors must have free space at a bottom corner or hidden windows show on a neighbour.
- Mission Control shows tiny windows (workaround `expose-group-apps`).
- "Displays have separate Spaces" should be off; with it on there are focus and performance bugs and a window cannot span monitors.
- Accessibility is unreliable for some apps, so polling and a mouse-up hook are used.
- Global hotkeys cannot distinguish left from right modifiers (Carbon hotkeys); an event tap move is tracked.
- Key conflicts with skhd, Karabiner and Raycast.
- Pre-1.0 policy: breaking changes allowed; the mutable tree has known rare bugs.
- Issues are not accepted directly; users open GitHub Discussions.

---

## 6. Side by side and implications for Tatami

### 6.1 Comparison matrix

| Dimension | BetterStage 2.2.1 | AeroSpace 0.21.3 | Tatami today (per repo docs) |
|---|---|---|---|
| Core abstraction | Stage (cross-monitor window group) | Workspace (per-monitor tree) | Stage (as BetterStage) |
| Layout engine | Native freeform plus snap, TabStack panes, legacy Bento | Always a tree: tiles and accordion | Native plus snap, TabStack (M3) |
| Hiding | Off-screen with journal, watchdog, optional SkyLight Spaces bridge | Corner parking, 1 px sliver, restore on quit | Off-screen with journal and minimize fallback (M1) |
| Private APIs | SkyLight, MultitouchSupport, symbolic hotkeys | One (`_AXUIElementGetWindow`) | None declared; gestures blocked on private API |
| Input | Carbon hotkeys, event taps, gestures, wheel, scroll | Carbon hotkeys only | Carbon hotkeys, scroll to switch |
| Automation surface | Custom Actions, URL scheme | Full CLI, socket, event stream, TOML | None external yet |
| Persistence and recovery | Checkpoints, continuity, undo transactions | Restore on quit; stateless otherwise | Journal, workspace saves, 20-step layout undo |
| Window rules | Routing and behaviour rules with live match preview | `on-window-detected` shell conditions | Routing and behaviour rules |
| AI | Hosted plus 20 BYO providers, Recipes | None (non-goal) | BYO, plan validation, Keychain |
| Switcher | ⌘Tab replacement | None (focus commands only) | None |
| Config | GUI plus backup and import | TOML only | GUI plus backup |
| Licence | Commercial, device-bound | MIT | Not decided |
| Distribution | Notarized Developer ID, Sparkle | Self-signed, Homebrew | Pre-release |

### 6.2 Recommendations

Prioritised for Tatami's PRD. "Adopt" means implement the behaviour in Tatami's own way.

1. **Adopt (P0): keep investing in recovery.** BetterStage's recovery vocabulary (lease, watchdog, quarantine, checkpoint, preserve unreadable state, newer-version read-only) and AeroSpace's "restore everything on quit" are the two proven defences. Add to M1: a schema version on every persisted file with a read-only fallback, and a one-click Rescue action.
2. **Adopt (P1): an external automation surface.** AeroSpace shows the value of a small versioned local protocol plus JSON queries and an event stream. Tatami should add a `tatami` CLI over a Unix socket (query stages, windows, displays; switch, send, snap; subscribe to events). This is cheap with the existing `TatamiCore` state model and differentiates against BetterStage, which has only a URL scheme.
3. **Adopt (P1): a ⌘Tab switcher.** It is the clearest 2.2.x feature the roadmap misses. Ship icons first, previews behind the existing Screen Recording consent.
4. **Decide (P1): macOS Spaces support.** BetterStage now models Spaces inside Workspaces and needs SkyLight and Mission Control automation to create Desktops. AeroSpace rejects Spaces outright. Recommendation: follow AeroSpace. Tatami stays on one Desktop per monitor, and Workspaces store Stages and layouts only. This keeps Tatami on public APIs.
5. **Adopt (P2): layout tree discipline from AeroSpace.** Normalization rules (flatten single children, alternate orientation), weight-based sizing, and MRU-based insertion are small, testable rules that fit `PaneLayout`. Add them as property tests in `PaneLayoutTests`.
6. **Adopt (P2): rules with live match preview and stale-edit detection** (BetterStage), and shell-free conditions only (AeroSpace's shell `if` is powerful but a security and support burden for a GUI product).
7. **Defer: trackpad gestures, shared windows, Bento Box, hosted AI and licensing.** Each carries private-API, identity or backend cost without a core-thesis payoff.
8. **Avoid: replicating animation, borders, or ricing.** Both products show these are not required for adoption.

### 6.3 Open questions for the product owner

- Should Tatami target keyboard-first users (AeroSpace's audience) or visual organizers (BetterStage's audience) for the first public release? The plan above serves both but weights recovery and automation first.
- Is a CLI in scope for v1, or a post-launch addition?
- Is a Spaces-free position acceptable for the "Workspace" feature?
- What licensing model will Tatami use, given that BetterStage's device-bound lease and fail-closed marker are a large engineering area?

---

## 7. Appendix

### 7.1 Evidence index (local, gitignored under `.context/`)

| File | Content |
|---|---|
| `.context/rea/` | Clone of github.com/morluto/rea |
| `.context/reabin/` | Local install of `rea-agents` 6.4.0 |
| `.context/out/bs-plist.json`, `as-plist.json` | `inspect-plist` results |
| `.context/out/bs-sig.json`, `as-sig.json` | `inspect-signature` results |
| `.context/out/bs-macho.json`, `as-macho.json`, `as-cli-macho.json` | `inspect-macho` results (dependencies, imports, exports, segments) |
| `.context/out/bs-artifact.json`, `as-artifact.json` | `inspect-artifact` results |
| `.context/out/bs-strings.json` | BetterStage `Localizable.strings` as JSON |
| `.context/out/bs-binstrings.txt`, `as-binstrings.txt` | `strings -a` of the main executables |
| `.context/aero/src`, `.context/aero/rel` | AeroSpace source clone and v0.21.3-Beta release |

### 7.2 Reproduce

```sh
mkdir -p .context && cd .context
git clone --depth 1 https://github.com/morluto/rea.git
npm install --prefix reabin rea-agents@latest
REA=$PWD/reabin/node_modules/.bin/rea
$REA doctor
$REA inspect-plist /Applications/BetterStage.app --json     # target is the .app, not Info.plist
$REA inspect-signature /Applications/BetterStage.app --json
$REA inspect-macho /Applications/BetterStage.app/Contents/MacOS/BetterStage --json
gh release download v0.21.3-Beta -R nikitabobko/AeroSpace -p '*.zip'
```

### 7.3 Extending the analysis

Installing Hopper, Ghidra or IDA and setting `HOPPER_LAUNCHER_PATH` or `GHIDRA_INSTALL_DIR` would unlock REA's `decompile`, `trace`, `function`, `search` and `observe-native-calls` on the BetterStage binary. Useful follow-ups: trace the Stage switch path to measure what it does per window, find the hide-failure conditions behind the "window hiding unavailable" banner, and confirm the Option plus scroll handler.

### 7.4 Conventions

Product names, bundle identifiers, framework names and Swift type names are quoted as facts about shipped software for compatibility and interoperability analysis. Requirement IDs (`BS-`, `AS-`) are local to this document and do not correspond to IDs in `betterstage-inspired-prd.md`.
