# Nexus UI Redesign — June 2026

## Direction

**Theme:** quiet pro

- developer-first, minimal, calm
- premium native feel before decorative flourish
- system typography with disciplined SF Mono accents
- soft depth, thin separators, restrained color
- Liquid Glass only for lightweight chrome and controls, never for core reading surfaces

## Visual rules

- light + dark mode both first-class
- content surfaces stay highly legible and low-noise
- cards read like precision instruments, not marketing tiles
- accent colors are semantic: blue = action, green = healthy/ready, amber = warning, red = failure
- rounded corners stay consistent and slightly tighter than today
- shadows stay soft and low spread
- motion stays quick, quiet, and state-driven

## Scope

### macOS

- redesign shared macOS theme tokens and panel chrome
- refresh sidebar, workspace overview, provider detail, and session header/composer
- remove forced dark mode
- keep NavigationSplitView architecture intact

### iOS Remote Client

- redesign shared iOS theme tokens and panel chrome
- refresh home, workspace, provider, and session surfaces
- add Liquid Glass to selective chrome where it improves hierarchy
- remove forced dark mode

### Shared session presentation

- update structured session bubble styling to match the new system
- preserve existing behavior and data flow

## Verification checklist (Phase 1)

- [x] macOS app builds
- [x] Modules tests for touched presentation code pass
- [x] iOS simulator build/run works with `NEXUS_REMOTE_CLIENT_FIXTURE=streaming-feed-profile`
- [x] verify home → workspace → provider → session navigation
- [x] verify session composer send flow in fixture
- [x] verify light mode
- [x] verify dark mode

## Work log

### Slice 1

- add redesign brief

### Slice 2

- theme system overhaul
- adaptive light/dark tokens
- shared panel/button refinements

### Slice 3

- macOS shell refresh
- iOS shell refresh
- structured session styling refresh

### Slice 4

- simulator verification
- lint/tests
- lowered iOS deployment target from 26.5 to 26.4 so the installed 26.4 simulator runtime can actually run Nexus
- validated light home, dark home, and light session screens in the simulator
- validated home → workspace → provider → session navigation in the simulator

---

## Phase 2 — IA, navigation, and component system (2026-06-20)

Phase 1 covered theme tokens and surface styling. Phase 2 builds the navigation and
component-system layer on top of it: command palette, status-token consolidation,
provider identity accents, and menu-bar discoverability. See conversation context for
the full IA proposal; this log tracks what actually landed against that proposal,
including where reality (existing `ContentView.swift` architecture) diverged from the
original pitch.

### Reality check against the original pitch (revisited — see Slice 11)

- The macOS shell **was** a **2-column** `NavigationSplitView` (sidebar + one detail
  pane), not a 3-column workspace/provider/session layout, with Workspace Overview,
  Provider Detail, and Focused Session all rendering inside the single detail pane via
  `SidebarSelection`. The first pass through this doc treated "there's no middle
  column today" as a reason the 3-pane pitch didn't apply. That was the wrong call —
  the absence of the structure was the actual work item, not a reason to skip it. See
  Slice 11 below, which builds it for real.
- A Quick Switch sheet already exists (`QuickSwitchSearchCoordinator` +
  `quickSwitchSheet` in `ContentView.swift`), workspace-first with debounced search.
  This is the right foundation for the proposed Command Palette — extend it, don't
  replace it.
- Status color/symbol logic was already **duplicated and drifting** across
  `providerHealthColor` (theme tokens), `hostValidationStateColor`/
  `workspaceAvailabilityStateColor` (raw SwiftUI `.green`/`.orange`/`.red`/`.secondary`),
  and a third unused `NexusMacTheme.statusColor(String)` helper. This is real
  inconsistency, not a hypothetical — confirmed before touching anything.
- No provider-identity accent colors exist anywhere yet. Card/header tinting is
  entirely health-driven today.

### Slice 5 — status tone consolidation ✅

- [x] Add one shared `NexusStatusTone` model (healthy/warning/critical/blocked/unknown)
      with color + SF Symbol, used by Provider Health, Host Validation, Workspace
      Availability, and Session State. Lives in `nexus/NexusStatusTone.swift`, with
      platform-specific `color` extensions for macOS and iOS.
- [x] Replace the three drifting color/symbol functions in `ContentView.swift`
      (`providerHealthColor`, `sessionStateColor`, `hostValidationStateColor`/`Symbol`,
      `workspaceAvailabilityStateColor`/`Symbol`) with tone-based mappings; delete the
      dead `NexusMacTheme.statusColor(String)` helper.
- [x] Apply the same consolidation to iOS: removed `RemoteClientHomeView.swift`'s
      duplicate `providerHealthColor`/`remoteSessionStateColor` helpers, which used the
      same colors as macOS's theme tokens (parity was already correct there — the real
      drift was macOS's raw `.green`/`.orange`/`.red`/`.secondary` in Host Validation and
      Workspace Availability vs. theme tokens everywhere else).
- [x] Verified: macOS + iOS Simulator builds both succeed, `./scripts/lint-swift.sh`
      passes. Commit `ea951f6`.

### Slice 6 — provider identity accents ✅

- [x] Added `claudeAccent`/`codexAccent`/`piAccent`/`ibmBobAccent` to
      `MacDesignSystem.swift` and `IOSDesignSystem.swift`, plus a
      `providerAccent(_ id: ProviderID)` accessor on each theme, distinct from the
      existing semantic gold/teal/coral tones.
- [x] Applied provider accent to: `ProviderCard` icon glyph (mac + iOS), Provider Detail
      header icon (mac), Focused Session header provider name text color (mac + iOS).
      Health/state color stays on status pills and panel tints — provider accent is
      identity-only, never a substitute for health signal.
- [x] Verified in the iOS Simulator (Pi provider card and "Pi" agent row render in the
      violet identity accent against the existing fixture data) and in the running
      macOS app against real local data (Codex blue, Claude terracotta, IBM Bob steel
      blue, Pi violet all visibly distinct in the workspace overview). Commit `df8a697`.

### Slice 7 — command palette (⌘K) ✅

- [x] Promoted the existing Quick Switch sheet (`nexus/NexusCommandPalette.swift` +
      `ContentView.swift`) into a Command Palette: kept workspace-first search, added a
      ranked Actions section (New Local Workspace, New Remote Workspace, New Workspace
      Group, Hosts, Remote Access) filtered by the same query text as navigation
      results.
- [x] Bound `⌘K` to the palette via the macOS "Go" menu (see Slice 8) rather than
      duplicating the shortcut on the sidebar search button, to avoid two competing
      claims on the same shortcut.
- [x] Verified in the running macOS app: opening via Go menu, typing "remote" correctly
      narrows the Actions section to New Remote Workspace / Hosts / Remote Access.

### Slice 8 — menu bar discoverability ✅

- [x] Added `.commands` in `nexusApp.swift`: `File` gets New Local Workspace (⌘N), New
      Remote Workspace (⇧⌘N), New Workspace Group; a new `Go` menu gets Command
      Palette… (⌘K); a new `Remote` menu gets Hosts… and Remote Access…. Menu items post
      `NotificationCenter` notifications (`nexus/NexusCommandPalette.swift`) that
      `ContentView` observes via `.onReceive`, since the App scene doesn't own
      `ContentView`'s local sheet/selection state.
- [x] Verified in the running macOS app: Go and Remote menus appear with the expected
      items and shortcuts; Go > Command Palette… opens the palette.

### Slice 9 — Settings scene (⌘,) ✅

- [x] Replaced the Hosts/Remote Access sheets with a real macOS `Settings` scene
      (`nexus/NexusSettingsScene.swift`): a native `TabView` with Hosts and Remote
      Access tabs, opened via ⌘, or the existing Remote menu / toolbar "…" menu /
      Command Palette entries, all routed through `@Environment(\.openSettings)`.
- [x] `HostManagementView`/`RemoteAccessManagementView` dropped their `isPresented`
      binding and "Done" button — they're persistent Settings content now, not sheets.
- [x] Scoped down from the original Providers/Advanced/General pitch: there's no real
      provider configuration or app-level preference to show in those tabs yet (no
      `@AppStorage` or provider-config model exists anywhere in the app today), so
      adding empty placeholder tabs would be exactly the kind of premature scaffolding
      worth avoiding. Hosts and Remote Access are the only two real surfaces today.
- [x] Verified live in the running macOS app: ⌘, opens Settings, both tabs render
      against real local data (a saved Host with validation diagnostics; Remote Access
      enabled state and Paired Devices), CPU stays at 0% through activation and tab
      switching.

### Slice 10 — Session > Take Controller menu command ✅

- [x] Added a `Session` menu with "Take Controller", enabled only when a Paired Device
      currently holds Controller for the focused Session. `ContentView` publishes
      availability via `.focusedValue(\.nexusSessionControllerIsTakeable, Bool)`; the
      App reads it with `@FocusedValue` to enable/disable the menu item.
- [x] `NexusAppModel.reclaimFocusedSessionController()` resizes the focused Session to
      its current size, which is the same mechanism that already implicitly reclaims
      Mac Controller on input/resize (`SessionControllerRegistry.claimMacControl`) —
      no new Service/IPC surface needed, and nothing visibly reflows.
- [x] **Caught and fixed a real bug during manual verification**, not a regression from
      repeated test relaunches: the first `FocusedValue` carried a closure-bearing,
      non-`Equatable` struct. SwiftUI can't diff non-Equatable focused values, so every
      `ContentView` render republished a "changed" value, re-triggering the App's Scene
      body and `ContentView`'s body in an infinite loop — invisible while the app was
      backgrounded (no visible symptom, 0% CPU), ~100% CPU the instant the window
      became active. Fixed by carrying a plain `Bool` through `FocusedValue` and
      keeping the actual action on the existing `NotificationCenter` path. Lesson:
      `@FocusedValue` payloads must stay plain Equatable values, never closures.
- [x] Verified live: CPU stays at 0% through window activation and Settings tab
      switching after the fix.

### Slice 11 — 3-pane navigation, collapsing to 2 ✅

- [x] Replaced the single-detail-pane `NavigationSplitView` with a structural switch in
      `ContentView.body`: when no Session is focused, a 3-column
      `NavigationSplitView` (sidebar | middle = Workspace Overview/Provider/Group
      Detail | detail = a quiet "No Session focused" placeholder); when a Session
      *is* focused, a 2-column `NavigationSplitView` (sidebar | Focused Session,
      full-bleed). Three panes is correct for browsing; two panes is correct for
      working — the middle column gets out of the way entirely rather than lingering
      next to a session the developer already opened.
- [x] `detailView`/`detailPadding` split into `middleColumnView` (every
      non-`.session` `SidebarSelection` case, unchanged rendering logic from the old
      single-pane switch), `focusedSessionColumnView` (the old `.session` case, now
      full-bleed in its own column), and `sessionPlaceholderColumnView` (new, shown
      only in the 3-pane branch). `isSessionFocused` is the single source of truth
      driving which `NavigationSplitView` arity renders.
- [x] Gave the middle column its own `navigationSplitViewColumnWidth(min: 340, ideal:
      420, max: 560)` so Workspace Overview/Provider Detail have real room next to the
      sidebar's existing `min: 280, ideal: 310`.
- [x] Verified live in the running macOS app against real local data: Home renders as
      sidebar + Workspace Overview + "No Session focused" placeholder; opening an
      already-ready Session (IBM Bob's default session) collapses immediately to
      sidebar + full-bleed session transcript; navigating back to the Workspace via
      the Command Palette correctly re-expands to the 3-pane layout. Both directions
      of the transition confirmed with screenshots.
- Note: `List(selection:)` sidebar row clicks were unreliable under AppleScript/AX
  synthetic clicks during verification (a known automation quirk with this app, not a
  product regression — Buttons and the Command Palette's button-backed navigation
  rows clicked reliably throughout). Verified the reverse (session → workspace)
  transition via the Command Palette instead.
- Not done: an animated/width-collapsing transition between the two layouts. This is a
  structural view swap (SwiftUI tears down and rebuilds the column tree), which is
  visually a snap, not a slide. Worth a follow-up with `matchedGeometryEffect` or a
  custom transition if the snap reads as jarring in practice.

### Explicitly deferred (not in this pass)

- Providers and Advanced/General Settings tabs — no real content exists for them yet
  (see Slice 9 note). Worth adding once there's an actual provider-configuration or
  app-preference model to back them.
- Navigation-model items from the original pitch beyond the 3-pane layout itself:
  session selection restoration on relaunch, non-modal approval banners scoped to
  session/provider/host chrome, and Session UI state (scroll position, composer
  draft) surviving a provider switch. None of these are disproven by reality — they
  just haven't been tackled yet.
- Component renames into the proposed named system (`WorkspaceRow`, `SessionLaneRow`,
  `ControllerBadge`, `HostValidationPill`, `AgentTurnStack`, etc.) — the views exist
  and work, just not extracted into discrete named types yet.
