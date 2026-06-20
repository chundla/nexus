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

### Reality check against the original pitch

- The macOS shell is a **2-column** `NavigationSplitView` (sidebar + one detail pane),
  not a 3-column workspace/provider/session layout. Workspace Overview, Provider
  Detail, and Focused Session all already render inside the single detail pane via
  `SidebarSelection`. There is no middle column to "collapse" when a Session is
  focused — that part of the original pitch doesn't apply as stated. The Focused
  Session header (`sessionDetailContent`) is already a compact breadcrumb-style panel,
  not a full overview, so the core goal (don't bury the session under workspace chrome)
  is already substantially met.
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
- Deferred: Session-specific menu items (e.g. "Take Controller") were not added in this
  pass — they need live focused-session context that the App-scene notification pattern
  doesn't carry cleanly yet. Worth a follow-up once there's a concrete need.

### Explicitly deferred (not in this pass)

- Settings scene (⌘,) consolidating Hosts/Remote Access/Providers/Advanced — Hosts and
  Remote Access currently live as sheets, which is a real change in surface area, not a
  style pass. Tracked here so it isn't lost, not attempted in Phase 2.
- Any 3-pane / collapsing-pane navigation change — not applicable; see reality check
  above.
- Session-specific menu commands (see Slice 8 note above).
