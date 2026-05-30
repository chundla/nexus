# Session Presentation deepening

This document records the landed `NexusSessionPresentation` seam.

Completed issues:
- #149 Create the `NexusSessionPresentation` Module and move the structured **Session Presentation** test surface
- #150 Route macOS structured **Session** screens through the root **Session Presentation**
- #151 Route iPhone structured **Session** screens through the root **Session Presentation**
- #152 Move structured slash-command menu policy behind the **Session Presentation** seam on both clients
- #153 Delete shallow structured presentation leftovers and document the seam

## Current seam

`NexusSessionPresentation` is the shared client-facing **Module** for structured **Session Presentation**.

It owns:
- one root `StructuredSessionPresentation` built from `SessionScreen`, writer authority, draft text, and action-in-flight state
- shared activity-row projection
- conversation-role classification
- pending **Approval Request** filtering
- shared composer and send-affordance state
- shared structured slash-command menu state and insertion behavior
- provider-aware structured copy that callers render directly

It does not own:
- primary **Session Surface** selection before a caller enters structured presentation
- platform-specific SwiftUI layout, theme, focus, scroll, or animation
- provider-module recovery policy that belongs in `NexusService`
- terminal-backed **Session Surface** rendering

## UI adapters

The shared seam now has two real UI **Adapter**s:
- `nexus/ContentView.swift` for the macOS structured **Session Surface**
- `nexus/RemoteClientHomeView.swift` for the iPhone structured **Session Surface**

Those adapters import `NexusSessionPresentation` directly and keep only platform-specific UI behavior outside the shared **Module**.

The former app-local structured presentation shim no longer owns shared policy.

## Test surface

`NexusSessionPresentation`'s public interface is the main test surface.

Keep coverage centered on:
- shared scenario tests in `Modules/Tests/NexusSessionPresentationTests`
- thin app tests that prove the macOS and iPhone adapters stay wired to the shared presentation state where needed

Avoid rebuilding shared structured presentation policy in app-local helpers just to test it again.

## Relationship to other seams

This seam stays aligned with ADR-0028 and ADR-0029:
- the shared **Session** stream remains canonical, so structured presentation is a projection rather than a competing source of truth
- the primary **Session Surface** remains explicit on `SessionScreen`, while client support stays a separate concern

Terminal work is explicitly out of scope here. Shared terminal projection remains follow-up `NexusTerminal` work.
