# Milestone Eleven

## Goal

> **Historical note**
> This document captures the intended scope and decisions for Milestone Eleven at the time it was written. For current terminology and rollout status, prefer `README.md` (provider matrix), `ARCHITECTURE.md`, and `docs/architecture/milestone-14.md`.

Prove that a trusted iPhone **Remote Client** can fully render and operate structured **Sessions** on a **Paired Mac** by extending the shared structured **Session Surface** across the dedicated remote API, keeping the existing **Controller** and **Pairing** model intact, and avoiding any user-facing terminal fallback for structured **Sessions**.

## Rollout status

> **Checkout status:** **Implemented** in this repo for the paths named in this milestone (local Pi, local Codex, remote Codex). Remote Pi and IBM Bob (local and remote) gained the same structured iPhone treatment in Milestones Twelve–Fourteen.

Milestone Eleven turns the structured **Session Surface** on iPhone from inspect-only to supported and operable for every currently launchable structured path on a **Paired Mac**. That includes local Pi, local Codex, and remote Codex. Terminal-backed **Sessions** remain terminal-backed on iPhone, remote Pi remains unsupported, and provider-native authentication remains provider-native rather than becoming a new iPhone-specific flow in this milestone.

## Success criteria

- iPhone can launch or resume the default structured **Session** for any currently launchable structured **Provider** on the active **Paired Mac**
- iPhone can create additional structured **Named Sessions** for any currently launchable structured **Provider** on the active **Paired Mac**
- iPhone can inspect, relaunch, stop, and delete structured **Session Records** using the same lifecycle rules that already apply to other **Session Records**
- if structured launch or create fails, Nexus persists an inspectable failed **Session Record**, opens it immediately on iPhone, and allows relaunch from there
- iPhone renders structured **Sessions** through the shared structured primary **Session Surface** rather than pretending they are terminal **Sessions**
- iPhone renders the full shared structured **Session** stream categories already used on macOS, including messages, **Approval Requests**, approval decisions, progress, diffs, command activity, errors, and completion state
- iPhone can send structured prompts through a generic remote **Session** input action rather than overloading terminal-text routes
- iPhone can approve or deny structured **Approval Requests** when it is the current **Controller**
- structured prompt submission and structured **Approval Request** decisions are enabled only for the current **Controller**; **Viewers** can still inspect the same **Session** with visible but disabled write affordances
- iPhone continues to attach to **Sessions** as a **Viewer** by default after open, launch, create, relaunch, reconnect, and failure recovery; taking **Controller** remains explicit
- Mac reclaim, iPhone background release, stale-screen reconnect, and explicit retake-**Controller** behavior remain aligned with existing iPhone **Session** behavior
- **Stop Session** remains a lifecycle action distinct from **Controller**-gated Session-writing actions
- `prelaunchPrimarySurface` remains part of the shared model, but iPhone no longer blocks structured launch/create just because the resulting primary **Session Surface** is structured
- the dedicated remote API exposes a generic structured-input route and a first-class approval-decision route using domain concepts rather than terminal-only transport concepts
- no extra Mac-side approval layer is added for trusted **Paired Devices** performing structured **Session** actions in this milestone
- provider-native authentication remains provider-native; if **Provider Health** says auth is required, launch/create stays blocked with truthful health guidance rather than introducing new iPhone auth UX
- durable/full structured activity-history backfill is not required; parity applies to the current shared structured **Session** stream
- automated coverage proves the behavior across service/runtime, dedicated remote-network API, iPhone model, and shared structured-presentation seams

## Scope

### In

- iPhone structured **Session Surface** rendering for all currently launchable structured **Sessions** on a **Paired Mac**
- full iPhone structured **Session** operation, including launch, create, relaunch, prompt submission, **Approval Request** decisions, stop, and delete under existing lifecycle and trust rules
- shared cross-platform structured presentation mapping and copy so macOS and iPhone render the same canonical structured **Session** model consistently
- iPhone rendering of the full shared structured **Session** activity stream
- visible but disabled structured write affordances while iPhone is a **Viewer**, with guidance to take **Controller**
- explicit **Controller** takeover before structured prompt submission or **Approval Request** decisions
- continued viewer-by-default attachment after launch, create, relaunch, reconnect, and failure recovery
- continued action placement in existing iPhone navigation surfaces, especially **Provider detail** and the focused **Session** screen
- a dedicated remote `POST /remote-client/sessions/{sessionID}/input` action for generic **Session** input
- a dedicated remote `POST /remote-client/sessions/{sessionID}/approval-requests/{approvalRequestID}/decision` action for shared **Approval Request** decisions
- continued terminal-specific remote routes for terminal **Session Surfaces** where they remain appropriate
- compatibility-preserving propagation of structured **Session Surface Support**, **Controller** state, pending **Approval Requests**, and shared structured activity through service, IPC, and dedicated remote API boundaries
- continued use of `prelaunchPrimarySurface` as a shared signal across clients
- failed structured launch/create behavior on iPhone that reuses the existing failed-**Session Record** pattern
- test coverage across service/runtime, dedicated remote API, iPhone state model, and shared presentation/copy helpers

### Out

- provider-breadth expansion solely to support this milestone
- remote Pi execution on **Remote Workspaces**
- migration of terminal-backed **Providers** such as Claude onto a structured or protocol-native path
- IBM Bob implementation
- provider-native authentication redesign or new iPhone-specific auth UX
- extra Mac-side confirmation prompts for structured write actions from trusted **Paired Devices**
- user-facing terminal fallback for structured **Sessions** on iPhone
- automatic **Controller** takeover after launch, create, relaunch, reconnect, or foreground return
- changes to existing stop/delete semantics
- durable or full structured activity-history backfill
- broad new workspace-overview or provider-card shortcut actions on iPhone
- a persistent Nexus helper installation on the **Host**
- broad iPad-first or iPad-specific UX work

## UX minimums

### iPhone Provider detail

- structured **Providers** keep using the existing iPhone **Provider detail** shape
- default **Session**, **Named Sessions**, and failed **Session Records** remain visible in the same product model
- launch and create actions stay in **Provider detail** rather than moving to new overview shortcuts
- if a structured **Provider** is launchable on the active **Paired Mac**, iPhone may use its existing launch and create affordances even though the resulting **Session Surface** is structured
- disabled states continue to explain product-support limits through **Provider Capability** and readiness limits through **Provider Health**
- auth-required states stay blocked with truthful provider-health guidance rather than offering a fake structured auth flow on iPhone

### iPhone Session screen

- structured **Sessions** render as structured/shared activity rather than as terminal emulation
- structured-session copy uses generic shared **Session** language such as prompts, shared activity, and **Approval Requests** rather than terminal-only wording
- the structured **Session** screen shows the same shared activity categories already surfaced on macOS, adapted to phone layout
- pending **Approval Requests** are visible on iPhone
- when iPhone is the **Viewer**, structured prompt composer and approval actions remain visible but disabled, with guidance to take **Controller**
- when iPhone is the **Controller**, structured prompt composer and approval actions are enabled
- a successfully launched or created structured **Session** opens immediately on iPhone as a **Viewer** by default
- a failed launch or create opens immediately into failed **Session Record** inspection with relaunch capability
- Stop Session remains visible with confirmation and does not require taking **Controller** first
- structured **Sessions** do not expose a user-facing terminal fallback on iPhone

### iPhone reconnect and recovery

- stale-session reconnect behavior remains the same as the current iPhone **Session** model
- reconnect preserves last known content as stale read-only until refresh or observation resumes
- reconnect returns iPhone to **Viewer** status by default
- users explicitly retake **Controller** when they want to resume structured write actions
- relaunch continues to be explicit when a structured **Session Record** is inspectable but not running

## Core rules

- Milestone Eleven is a **Remote Client** depth milestone, not a provider-breadth or provider-auth redesign milestone
- structured **Session Surface Support** on iPhone is supported for every currently launchable structured **Session** path on a **Paired Mac**
- **Session Surface Support** remains separate from **Controller** state; surface support answers whether iPhone can present and operate the surface type at all, while **Controller** answers whether this attached client may perform Session-writing actions now
- the **Controller** owns all Session-writing actions, including structured prompts and **Approval Request** decisions
- **Viewer** and **Controller** semantics stay shared across terminal and structured **Session Surfaces**
- for structured **Sessions**, **Controller** is a writer-authority concept rather than a user-facing terminal-size concept
- structured **Sessions** stay structured on iPhone; Nexus does not fake a terminal for them
- iPhone stays workspace-first and keeps existing action placement under **Workspace** -> **Provider** -> **Session** navigation
- launch/create/open/reconnect continue to attach iPhone as a **Viewer** by default
- **Stop Session** and **Delete Session Record** remain separate lifecycle actions with unchanged semantics
- trusted **Paired Devices** continue to be authorized against their **Paired Mac** as a whole, with no extra Mac-side confirmation layer added in this milestone
- provider-native authentication remains provider-native; **Provider Health** stays the source of truth for auth-blocked launchability
- terminal-specific remote routes remain valid for terminal **Session Surfaces**, but generic structured prompt submission uses the new domain-first remote **Session** input route
- durable/full structured activity-history backfill remains out of scope in this milestone
- remote Claude remains terminal-backed, remote Pi remains unsupported, and IBM Bob remains non-launchable in this milestone

## Open implementation choices

- exact cross-platform extraction shape for the shared structured presentation helper now that it must serve both macOS and iPhone
- exact iPhone copy for viewer-disabled structured prompt and **Approval Request** affordances
- exact dedicated remote request-body shape for generic structured **Session** input
- exact dedicated remote request-body shape for remote **Approval Request** decisions while preserving the shared `ApprovalRequestDecision` enum semantics
- exact touched-seam test matrix and fixture reuse strategy across `Modules/Tests/NexusServiceTests`, `nexusTests/RemotePairingNetworkTests.swift`, `nexusTests/RemoteClientPairingModelTests.swift`, and shared presentation tests
