# Milestone Nine

## Goal

> **Historical note**
> This document captures the intended scope and decisions for Milestone Nine at the time it was written. For current terminology and rollout status, prefer `README.md` (provider matrix), `ARCHITECTURE.md`, and `docs/architecture/milestone-14.md`.

Prove that Nexus now has a reusable protocol-native **Session** architecture by making Codex the second local protocol-native **Launchable Provider**, generalizing the shared structured **Session Surface**, and keeping existing terminal-backed remote and iPhone Codex flows stable.

## Rollout status

> **Checkout status:** **Implemented** in this repo. Remote Codex is structured now (Milestone Ten); IBM Bob is launchable locally and remotely (Milestones Thirteen–Fourteen).

Milestone Nine turns local Codex on local **Workspaces** into a protocol-native **Provider** path with a structured primary **Session Surface**. Remote Codex on **Remote Workspaces** and current iPhone Codex flows remain terminal-backed in this milestone. Claude stays on its existing terminal-backed path, and IBM Bob remains visible but non-launchable.

## Success criteria

- user can inspect local Codex **Provider Health** on a local **Workspace** using protocol-native readiness checks rather than terminal-only launch probes
- user can launch or resume the default local Codex **Session** for a **Workspace**
- user can create additional local Codex **Named Sessions**
- local Codex **Session Records** follow the same stop, relaunch, inspect, and delete rules as existing local **Session Records**
- existing local Codex **Session Records** from earlier milestones remain valid and relaunch through the new local protocol-native Codex runtime without recreation
- macOS renders local Codex through the shared structured primary **Session Surface** rather than a required terminal surface
- local Codex can emit app-native **Approval Requests** and macOS can approve or deny them through the shared Nexus approval flow
- Pi and Codex both run through a provider-neutral protocol-native runtime seam inside the **Background Service**
- provider-native continuation linkage is generic **Session Record** metadata rather than Pi-only persistence
- local protocol-native **Session** continuity survives relaunch when provider-native linkage allows it, but live local runtime is still not restored across **Background Service** restart
- the shared `SessionScreen` contract used by local IPC and the dedicated **Remote Client** API carries explicit primary **Session Surface** information rather than requiring clients to infer it from **Provider** identity
- the shared client contract distinguishes **Provider Capability** from client-specific **Session Surface Support**
- iPhone can browse and inspect local structured Codex **Session Records** on a **Paired Mac**, shows explicit unsupported-**Session Surface** guidance, and does not fake a terminal for those Sessions
- existing remote Codex and iPhone terminal-backed Codex flows remain launchable and behaviorally unchanged on supported paths
- shared structured-session copy and presentation no longer contain Pi-specific branding on provider-general surfaces
- automated coverage proves local structured Codex behavior, Pi/Codex shared structured presentation, remote/iPhone Codex terminal compatibility, and existing Claude stability on touched seams

## Scope

### In

- generalizing the protocol-native runtime seam in `NexusService` so Pi and Codex are sibling implementations rather than one-off paths
- a local protocol-native Codex runtime and adapter owned by the **Background Service**
- local Codex **Provider Health** based on executable resolution, version detection when possible, protocol startup or handshake readiness, light auth-readiness detection where feasible, and other Codex-specific launch prerequisites as needed
- local Codex default **Session** launch/resume and **Named Session** creation
- full local Codex **Session Record** lifecycle parity including stop, relaunch, inspect, and delete
- generic provider-native continuation linkage stored as mutable adapter metadata on the **Session Record**
- preservation of local Codex **Session Record** identity across the migration from terminal-backed local Codex to protocol-native local Codex
- provider-general structured macOS **Session** presentation shared by Pi and Codex
- extraction of shared structured-session presentation helpers into a `NexusSessionPresentation` boundary if needed to keep multi-provider structured presentation coherent
- explicit primary **Session Surface** modeling in shared domain and IPC models
- explicit **Session Surface Support** modeling for clients that can browse a **Session** but cannot yet present or operate its primary surface
- provider-aware shared copy for structured **Session** surfaces, restart messaging, and composer text
- app-native **Approval Request** handling for local protocol-native Codex through the shared approval model
- shared-first **Session** event projection for messages, **Approval Requests**, progress, diffs, command activity, errors, and completion state
- compatibility-preserving propagation of primary **Session Surface** through local IPC and the dedicated **Remote Client** API
- explicit unsupported-surface handling on iPhone for local structured Codex **Sessions** encountered on a **Paired Mac**
- automated coverage across service, local IPC, app-model, and dedicated **Remote Client** boundaries for the mixed-surface Codex rollout

### Out

- remote protocol-native Codex execution on **Remote Workspaces**
- structured Codex rendering or structured Codex control on iPhone
- a user-facing local Codex mode switch between terminal-backed and protocol-native execution
- migration of Claude onto a protocol-native runtime
- IBM Bob implementation
- new provider configuration UI
- broad **Provider Capability** expansion beyond default-session launch/resume and **Named Session** creation
- provider-specific extension payloads unless Codex proves the shared **Session** event model insufficient
- broad **Launch Snapshot** expansion beyond generic fields required by more than one protocol-native **Provider**
- live local protocol-native runtime restoration across **Background Service** restart
- remote SSH/tmux contract changes

## UX minimums

### Workspace overview

- Codex appears in the existing provider-card model on local **Workspaces**
- a launchable local Codex card shows actionable default-**Session** affordance
- local Codex readiness language uses **Provider Health** and **Provider Capability** terminology rather than terminal-specific wording
- touched shared overview surfaces no longer special-case Pi wording for structured **Sessions**

### Provider detail

- local Codex uses the same provider-detail structure as other **Providers**
- default **Session**, **Named Sessions**, and failed **Session Records** remain in the same product model
- launch and create affordances follow service-owned **Provider Capability** state
- disabled actions continue to use capability reasons for product-support limits and health summaries for readiness limits

### Session screen on macOS

- local Codex uses the shared structured primary **Session Surface** already proven by Pi, with provider-aware copy rather than Pi-specific copy
- the structured **Session Surface** is useful without a required terminal fallback
- Codex **Approval Requests** appear through the shared app-native approval UI
- touched macOS structured-session chrome uses generic language such as shared activity, prompts, connection state, and restart guidance with provider-aware inserts where helpful

### iPhone Remote Client

- iPhone continues to use terminal-backed Codex flows on supported remote/terminal-backed paths
- when iPhone encounters a local structured Codex **Session** on a **Paired Mac**, the **Session** remains visible and inspectable rather than hidden
- iPhone shows explicit unsupported-**Session Surface** guidance for local structured Codex **Sessions** instead of pretending they are terminal **Sessions**
- iPhone disables launch, create, and control actions that would require operating an unsupported primary **Session Surface**

## Core rules

- Milestone Nine is a protocol-native **Session** generalization milestone, not a remote-expansion milestone
- local Codex is the only new fully protocol-native **Launchable Provider** in this milestone
- local Codex replaces the previous local terminal-backed Codex path; there is no user-facing local mode choice in this milestone
- the same **Provider** may expose different primary **Session Surfaces** on different **Workspace Targets** or runtimes
- primary **Session Surface** is explicit in the shared service-owned `SessionScreen` contract rather than inferred from **Provider** identity
- a **Session** may have one primary **Session Surface** plus secondary capabilities
- **Provider Capability** remains **Workspace**-target-scoped; client ability to present and operate a primary **Session Surface** is modeled separately as **Session Surface Support**
- the shared **Session** stream remains canonical; structured and terminal presentation are both projections of the same **Session** model
- shared **Session** events are preferred over provider-specific event dialects
- provider-native continuation linkage is generic mutable **Session Record** metadata, not part of the immutable **Launch Snapshot**
- **Launch Snapshot** stays minimal and generic unless more than one protocol-native **Provider** proves a shared expansion necessary
- live local protocol-native runtime is still not restored after **Background Service** restart in this milestone
- remote Codex and iPhone Codex keep their existing terminal-backed behavior on currently supported paths
- Claude remains terminal-backed, and IBM Bob remains non-launchable in this milestone

## Open implementation choices

- exact transport and process model for the local protocol-native Codex runtime
- exact generic persistence shape for provider-native continuation linkage across Pi and Codex
- exact shared domain and IPC representation for primary **Session Surface** and **Session Surface Support**
- exact extraction boundary for `NexusSessionPresentation`
- exact unsupported-surface messaging and affordance layout on iPhone
- exact minimal generic **Launch Snapshot** additions, if any, that Pi and Codex both require
