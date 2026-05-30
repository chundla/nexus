# Session Presentation deepening plan

This document records the agreed extraction plan for `NexusSessionPresentation`.

The target shape is one shared client-facing **Module** seam for structured **Session Presentation**. That **Module** owns shared projection from a structured `SessionScreen` into render-ready state, while the macOS and iPhone UI keep platform-specific **Adapter** implementations.

Related issues:
- #149 Create the NexusSessionPresentation Module and move the structured Session Presentation test surface
- #150 Route macOS structured Session screens through the root Session Presentation
- #151 Route iPhone structured Session screens through the root Session Presentation
- #152 Move structured slash-command menu policy behind the Session Presentation seam on both clients
- #153 Delete shallow structured presentation leftovers and document the Session Presentation seam

## Target seam

Shared modules keep:
- the shared `SessionScreen` contract in `NexusDomain`
- **Session Surface** selection before a caller enters structured **Session Presentation**
- platform-specific SwiftUI layout, theme, focus, scroll, and animation
- terminal-backed **Session Surface** rendering and terminal projection
- provider-owned recovery and interrupted-runtime text when that text belongs to the **Provider Module** seam rather than shared client presentation

`NexusSessionPresentation` owns:
- one root structured **Session Presentation** built from `SessionScreen`, writer authority, draft text, and action-in-flight state
- shared activity-row projection
- conversation-role classification
- pending **Approval Request** filtering
- shared composer and send-affordance state
- shared structured slash-command menu state and insertion behavior
- provider-aware structured copy that callers render directly

The macOS and iPhone UI are the two real **Adapter**s at this seam.

## Planned slices

1. Create the `NexusSessionPresentation` **Module** beside the current app-local helper.
   - move the current structured presentation types and pure projection logic behind the new **Interface**
   - keep behavior intentionally stable
   - move shared tests beside the new **Module**

2. Route the macOS structured **Session Surface** through the new seam.
   - make `nexus/ContentView.swift` consume one root structured **Session Presentation**
   - keep only platform-specific layout and interaction chrome in the macOS **Adapter**

3. Route the iPhone structured **Session Surface** through the new seam.
   - make `nexus/RemoteClientHomeView.swift` consume the same root structured **Session Presentation**
   - keep only platform-specific layout and interaction chrome in the iPhone **Adapter**

4. Move structured slash-command policy fully behind the seam.
   - shared query parsing
   - shared filtering and insertion behavior
   - provider-aware structured menu state
   - platform-specific menu layout stays in each **Adapter**

5. Delete shallow leftovers and document the seam.
   - remove remaining app-layer structured presentation leakage
   - keep terminal work out of scope
   - document `NexusSessionPresentation` as the shared **Module** and macOS/iPhone as the two UI **Adapter**s

## Migration order

Implement in this order:
1. #149
2. #150
3. #151
4. #152
5. #153

This proves the seam first, then proves both real **Adapter**s, then deletes the shallow leftovers.

## Test surface

`NexusSessionPresentation`'s **Interface** is the main test surface.

Add or keep:
- shared scenario tests for structured activity projection, conversation-role classification, pending **Approval Request** filtering, composer state, send-affordance state, and slash-command state
- thin macOS and iPhone tests proving each **Adapter** renders and wires the returned **Session Presentation** correctly

Reduce tests whose only job is proving app-layer files duplicated shared structured presentation policy, because those tests describe the shallow shape being deleted.

## Touched files

The deepest slices will likely touch:
- `Modules/Package.swift`
- `Modules/Sources/NexusSessionPresentation/*`
- `Modules/Tests/NexusSessionPresentationTests/*`
- `nexus/FocusedSessionPresentation.swift`
- `nexus/ContentView.swift`
- `nexus/RemoteClientHomeView.swift`
- `docs/architecture/modules.md`

## Non-goals

This refactor does not:
- extract terminal rendering into `NexusTerminal`
- change the shared `SessionScreen` domain contract
- redesign **Provider Module** ownership of provider-specific recovery policy
- change product meaning for **Session**, **Session Surface**, **Approval Request**, **Controller**, or **Viewer**

It changes where the structured **Session Surface** rules live so callers get more **leverage** from one **Interface** and maintainers get more **locality** from one **Module**.
