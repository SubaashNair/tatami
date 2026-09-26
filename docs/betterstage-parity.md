# BetterStage parity roadmap

Source: full crawl of betterstage.app docs, 94 how-to pages, tutorials, changelog, pricing (2.0.5 stable, 2.0.6-beta.4), and the @BetterStageApp YouTube channel (16 videos), 2026-09-24. PRD requirement IDs from [betterstage-inspired-prd.md](betterstage-inspired-prd.md). We implement behaviour, not their branding, copy, or assets.

Legend: ✅ done · 🟡 partial · ❌ missing

## Gap table

### Stages

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Named Stages across all displays, 9 max | ✅ | ✅ | STG-01 |
| Instant switch, no animation (off-screen parking) | ✅ <16 ms | ✅ measured with signposts | STG-03, DSP-06 |
| Switch 1–9, prev/next, cycle Opt+Tab | ✅ | 🟡 no Tab cycle | STG-04 |
| Option + scroll wheel to switch | ✅ | ❌ | new |
| New / close Stage shortcuts (Opt+N / Opt+X) | ✅ | ❌ | INP-03 |
| Drop window on + card creates Stage | ✅ | ❌ | new |
| Merge All Stages (Opt+M, menu bar) | ✅ | ❌ | STG-08 |
| Follow activated windows (auto-switch on focus) | ✅ default on | ✅ default on | STG-06 |
| Follow after sending / follow when routed | ✅ | 🟡 sending only | STG-05, RTE-02 |
| Cmd+` limited to active Stage | ✅ | ❌ | STG-07 |
| Classify existing windows on first run | ✅ | ❌ | ONB-06 |
| Shared windows across Stages (beta, Option-drag) | 🧪 | ❌ | new |

### Stages Bar

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Overlay bar with Stage cards (Opt+Up) | ✅ | ❌ (dashboard only) | BAR-01 |
| Top-centre hot edge, 0–2 s delay, notch option | ✅ | ❌ | BAR-02 |
| Live window thumbnails | ✅ | ❌ (icon schematic) | BAR-01 |
| Per-monitor window counts and mode labels | ✅ | ❌ | BAR-01 |
| Drag cards to reorder; drag window title bar onto a card | ✅ | 🟡 dashboard drag only | BAR-03 |
| Click name to rename, hover × to close | ✅ | ❌ | BAR-04 |
| Switch indicator (1.5 s, click-through) | ✅ | ❌ | BAR-05 |

### Window modes and tiling

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Enhanced Native (freeform + snap) | ✅ | ✅ | SNP-01 |
| 16 snap zones via keys | ✅ | ✅ | SNP-02 |
| Snap via edge drag | ⚠ docs disagree | ❌ | SNP-03 |
| Retile, then Re-stack (cascade) on repeat | ✅ | 🟡 grid only | SNP-04 |
| Screen padding per side | ✅ | ❌ (gap only) | SNP-05 |
| TabStack pane tree per display per Stage | ✅ | ❌ | TIL-01 |
| Drag overlay: edge split, centre join, swap zone, divider insert | ✅ | ❌ | TIL-02, TIL-05 |
| Tabs: switch (Ctrl+Opt+[ ]), reorder, move one, move stack, close variants | ✅ | ❌ | TIL-02, TIL-03 |
| Native-tab apps (Terminal, Ghostty) inside panes | ✅ | ❌ | TIL-10 |
| Independent divider resizing, ghost-frame preview | ✅ | ❌ | TIL-04 |
| Directional focus / move across panes and displays (Cmd+Opt+IJKL) | ✅ | ❌ | TIL-06 |
| Zoom / restore pane | ✅ | ❌ | TIL-07 |
| Launch App Here, Quit / Relaunch from tab | ✅ | ❌ | TIL-08, TIL-09 |
| Drop file on background tab | ✅ | ❌ | TIL-11 |
| New-window placement: Automatic / Active / Adjacent / Own pane | ✅ | ❌ | TIL-12 |
| Window behaviour: Automatic / Manage / Keep Floating, saved rules | ✅ | ❌ | TIL-13 |
| Even Out, Reflow as Grid (Cmd+Opt+G) | ✅ | ❌ | TIL-14 |
| Layout undo | ❌ none | ❌ | TIL-14 |
| Raise Floats | ✅ | ❌ | TIL-15 |
| Appearance: Comfortable / Compact / Custom, gaps, padding, tab styling | ✅ | ❌ | TIL-16 |
| Layout presets (5 built-in) + custom preset editor, default layout | ✅ | ❌ | LAY-01..04 |
| Cycle mode (Opt+B) per monitor | ✅ | ❌ | INP-03 |

### Snap Wheel and Custom Actions

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Radial wheel at pointer, inner + outer ring | ✅ | ❌ | WHL-01, WHL-03 |
| Triggers: middle-click, Ctrl+Opt hold, custom combos | ✅ | ❌ | WHL-02 |
| Triggers: 4/5-finger trackpad tap/click | ✅ | ❌ (needs private MultitouchSupport) | WHL-02 |
| Hold vs toggle, open delay, title-bar only | ✅ | ❌ | WHL-02 |
| Customisable slots, SF Symbols, Liquid Glass / Classic style | ✅ | ❌ | WHL-05, WHL-06 |
| Mode-adaptive actions | ✅ | ❌ | WHL-04 |
| Custom Actions: app, file, zsh command, Shortcut; trust prompt | ✅ | ❌ | ACT-01..06 |
| Custom submenus | ✅ | ❌ | WHL-07 |

### Shortcuts and input

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Every action rebindable; recorder, conflict warnings, "Move here" | ✅ | ❌ two fixed presets | INP-01, INP-02, INP-05 |
| Separate keyboard / mouse / trackpad bindings | ✅ | ❌ | INP-01 |
| European preset | ✅ | ✅ (as Standard default) | INP-04 |

### Displays and continuity

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Stable hardware display identity | ✅ | ✅ | DSP-02 |
| Pinned displays | ✅ | ❌ | DSP-04, DSP-05 |
| Disconnect: windows move to remaining displays / panes | ✅ | ✅ (panes in M3) | WSP-04 |
| Reconnect: Restore / Keep Current prompt | ✅ | ✅ | WSP-05 |
| Local hide corners option | ✅ | ✅ default | DSP-06 |
| Automatic continuity checkpoint (quit, wake, display change) | ✅ | ✅ | WSP-01..03 |
| Rescue Windows | ✅ | ✅ | DSP-07 |

### Workspaces, routing, exceptions

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Save / preview / load / rename / delete workspaces | ✅ | ✅ | WSP-06, WSP-07 |
| Capture current Stage only | ✅ | ❌ | WSP-06 |
| Open missing apps, per-workspace shortcuts | ✅ | ❌ | WSP-07, WSP-09 |
| Clean Load | ✅ | ❌ | WSP-10 |
| Missing display mapping on load | ✅ | ❌ | WSP-08 |
| Routing by app/title, ordered | ✅ | ✅ | RTE-01 |
| Route to display or pinned display; auto-create missing Stages | ✅ | ❌ | RTE-02, RTE-03 |
| Exclude from Staging | ✅ | ✅ | STG-09 |
| Float in Window Modes, Float Secondary Windows, Restore Defaults | ✅ | ❌ | RTE-06, RTE-07 |

### AI Staging

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Prompt → preview → apply → one-step undo | ✅ | ✅ | AIO-03, AIO-04 |
| Chat refinement, @mentions | ✅ | 🟡 Ask Again only | AIO-01 |
| Recipes (create, duplicate, default, preview prompt) | ✅ | ❌ | AIO-05 |
| ~25 providers, regions, temperature | ✅ | 🟡 8 presets | AIO-06, AIO-07, AIO-11 |
| AI chooses Window Mode per screen | ✅ | ❌ (needs TabStack) | AIO-03 |
| Paths / URLs in snapshot | ✅ | ❌ | AIO-02 |
| Managed AI subscription | ✅ | ❌ out of scope | AIO-08 |

### App shell

| Feature | BetterStage | Tatami | PRD |
|---|---|---|---|
| Menu-bar only, no Dock icon | ✅ | ❌ regular app | ONB-02 |
| Configurable menu-bar items | ✅ | ❌ | SET-02 |
| Menu bar: Merge, Pin Monitor, Rename Stage, restart | ✅ | 🟡 | SET-02 |
| Stage Manager detection | ✅ | ❌ (text only) | ONB-05 |
| Diagnostic log (10 MB rolling, reveal) | ✅ | ❌ | SET-09 |
| Reset Settings / Factory Reset | ✅ | ❌ | SET-06 |
| Appearance System / Light / Dark | ✅ | ❌ light only | new |
| Disable AXEnhancedUserInterface to stop resize animation | ✅ | ✅ (restored after each move) | new |
| Updates channel, licensing, trials | ✅ | ❌ out of scope for now | ONB-08, SET-07, SET-08 |
| Localisation (18 languages, beta) | 🧪 | ❌ | new |

## Where Tatami can be better

Grounded in gaps or contradictions in BetterStage's own docs:

1. **Layout undo.** BetterStage's docs say there is no TabStack undo. Tatami ships multi-step layout undo.
2. **Explainable state.** A "Why is this window here?" inspector naming the Stage, rule, mode, and display that placed it (PRD principle "No mystery state").
3. **Validated AI with reasons.** Already shipped: rejected actions are listed with why, titles can be withheld per provider, keys can never be redirected by an imported file.
4. **Keyboard-first tiling parity with AeroSpace** inside TabStack: every pane operation bindable, including resize and swap.
5. **Consistent, documented defaults.** BetterStage's docs contradict themselves on delete destination, Option-scroll default, edge snap, and TabStack tier. Tatami keeps one reference, tested.
6. **Free core.** No licensing layer; all nine Stages and TabStack available.

## Milestones

Ordered by dependency. Each milestone gets a design grilling, tests first in `TatamiCore`, review, and a commit per step.

| # | Milestone | Why here | Main items |
|---|---|---|---|
| M1 | **Engine foundations** | Everything else needs instant switching and live events | Off-screen parking with journaled recovery, AX observer pipeline off the main thread, stable display identity, continuity checkpoints, disconnect/reconnect, AXEnhancedUserInterface handling, Accessibility-revoked restore |
| M2 | **Stages polish** | Daily-use feel | Stages Bar overlay with hot edge, cards, drag/drop, rename/close; Opt+N/X/M/Tab, Option-scroll, follow settings, Cmd+` scoping, switch indicator, menu-bar-only mode, first-run classification |
| M3 | **TabStack core** | BetterStage 2's headline | Pane tree model, split/join/swap/insert, tabs, divider resize, directional focus/move, zoom, even out, reflow, layout undo, new-window placement, window behaviour rules, float exceptions, raise floats |
| M4 | **TabStack polish** | Makes it feel native | Drag overlay, appearance settings, presets and editor, native-tab apps, launch here, quit/relaunch, file drop on tab, per-monitor mode cycling |
| M5 | **Input** | Needed by wheel and power users | Full shortcut recorder with conflicts, mouse bindings, per-workspace shortcuts |
| M6 | **Snap Wheel and Custom Actions** | Mouse-first parity | Radial wheel, triggers (middle-click, modifier hold, combos), slots, styles, custom actions with trust model |
| M7 | **Displays and workspaces** | Multi-monitor users | Pinned displays, routing to displays, current-Stage capture, open missing apps, clean load, display mapping |
| M8 | **AI parity** | Builds on M3 | Recipes, @mentions and chat, provider list expansion, temperature, AI picks Window Mode |
| M9 | **Shell** | Finish | Configurable menu bar, diagnostics log, resets, dark mode, localisation |

Deferred with reason: trackpad tap triggers (private MultitouchSupport framework, fragile across macOS releases; revisit after M6), managed AI and licensing (no service to run).
