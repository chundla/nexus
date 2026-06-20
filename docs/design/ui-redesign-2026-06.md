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

### Slice 5 — status tone consolidation

- [x] Add one shared `NexusStatusTone` model (healthy/warning/critical/blocked/unknown)
      with color + SF Symbol, used by Provider Health, Host Validation, Workspace
      Availability, and Session State.
- [x] Replace the three drifting color/symbol functions in `ContentView.swift` with
      tone-based mappings; delete the dead `NexusMacTheme.statusColor(String)` helper.
- [x] Verify lint + a focused build.

### Slice 6 — provider identity accents

- [x] Add per-provider accent colors (Claude, Codex, Pi, IBM Bob) to
      `MacDesignSystem.swift` and `IOSDesignSystem.swift`, distinct from the existing
      semantic gold/teal/coral tones.
- [x] Apply provider accent to: `ProviderCard` icon glyph, Provider Detail header icon,
      Focused Session header provider glyph. Health/state color stays on status pills —
      provider accent is identity-only, never a substitute for health signal.
- [x] Verify lint + a focused build.

### Slice 7 — command palette (⌘K)

- [x] Promote the existing Quick Switch sheet into a real Command Palette: keep
      workspace-first search, add a ranked Actions section (New Workspace, New Named
      Session, Take Controller, Toggle Sidebar Mode, Hosts, Remote Access).
- [x] Bind `⌘K` globally (menu command + keyboard shortcut), not just the sidebar
      search button.
- [x] Verify lint + a focused build.

### Slice 8 — menu bar discoverability

- [x] Add `CommandMenu`s in `nexusApp.swift` mirroring the palette's actions, so every
      power action has a discoverable menu home, per HIG.
- [x] Verify lint + a focused build.

### Explicitly deferred (not in this pass)

- Settings scene (⌘,) consolidating Hosts/Remote Access/Providers/Advanced — Hosts and
  Remote Access currently live as sheets, which is a real change in surface area, not a
  style pass. Tracked here so it isn't lost, not attempted in Phase 2.
- Any 3-pane / collapsing-pane navigation change — not applicable; see reality check
  above.
