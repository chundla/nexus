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

## Verification checklist

- [ ] macOS app builds
- [ ] Modules tests for touched presentation code pass
- [ ] iOS simulator build/run works with `NEXUS_REMOTE_CLIENT_FIXTURE=streaming-feed-profile`
- [ ] verify home → workspace → provider → session navigation
- [ ] verify session composer send flow in fixture
- [ ] verify light mode
- [ ] verify dark mode

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
