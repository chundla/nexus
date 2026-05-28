# Milestone Twelve

## Goal

Prove that Nexus can make Pi a fully launchable protocol-native **Provider** on **Remote Workspaces** by reusing the existing service-owned remote structured **Session** architecture, keeping **tmux** as the **Remote Session Strategy** for durability, and extending the supported iPhone structured **Remote Client** experience to remote Pi without introducing any Pi-specific terminal fallback or iPhone-specific auth flow.

## Rollout status

Milestone Twelve turns Pi on **Remote Workspaces** into a protocol-native structured **Provider** path with full **Session Record** lifecycle parity on macOS and supported structured **Remote Client** parity on iPhone. Local Pi, local Codex, and remote Codex remain structured. Remote Claude remains terminal-backed, IBM Bob remains non-launchable, and this milestone does not broaden into top-level iOS app-target productization.

## Success criteria

- user can inspect remote Pi **Provider Health** on a **Remote Workspace** using the existing **Host Validation** -> **Workspace Availability** -> **Provider Health** dependency chain plus Pi-specific protocol-native readiness checks
- user can launch or resume the default remote Pi **Session** for a **Remote Workspace**
- user can create additional remote Pi **Named Sessions**
- remote Pi **Session Records** follow the same stop, relaunch, inspect, and delete rules as other structured remote **Session Records**
- macOS renders remote Pi through the shared structured primary **Session Surface** rather than a terminal surface
- iPhone can launch, create, inspect, relaunch, stop, delete, and operate remote Pi **Sessions** on a **Paired Mac** through the same structured **Session Surface** model already used for other supported structured **Sessions**
- remote Pi can emit app-native **Approval Requests** and macOS or iPhone can approve or deny them through the shared Nexus approval flow when acting as **Controller**
- the **Background Service** owns one live remote protocol bridge per remote Pi **Session**, and attached clients observe the shared Nexus **Session** rather than opening their own Host connections
- remote Pi runs on the **Host** rather than on the Mac, using the existing provider-neutral remote protocol-native runtime seam inside the **Background Service**
- **tmux** remains the **Remote Session Strategy** for remote Pi durability, but it is not the protocol transport and not the product-visible **Session Surface**
- the remote Pi protocol bridge uses raw SSH stdio without PTY allocation
- remote Pi launch and recovery use the resolved absolute remote executable path captured in the **Launch Snapshot**
- remote Pi **Provider Health** uses remote executable resolution plus a short-lived direct SSH Pi RPC readiness probe rather than a tmux-backed health probe
- explicit remote auth-readiness failure blocks remote Pi launchability with truthful provider-native guidance, while auth uncertainty may remain launchable with warning diagnostics
- tmux-backed remote Pi runtime remains recoverable after **Background Service** restart or bridge loss through explicit launch/resume, while simply inspecting the **Session Record** does not auto-reattach it
- if a known tmux-backed remote Pi runtime is gone, relaunch starts a fresh remote runtime and resumes persisted Pi linkage when valid
- if persisted Pi linkage is invalid, Nexus automatically falls back to a fresh remote Pi session while preserving the same Nexus **Session Record**
- if the live remote Pi protocol bridge drops while the remote runtime still exists, the **Session** becomes inspectable and explicitly recoverable without requiring automatic in-place reconnect
- iPhone structured support for remote Pi follows shared **Session Surface Support** rules rather than a Pi-specific local-versus-remote exception
- no persistent Nexus helper installation is required on the **Host** beyond SSH, **tmux**, and Pi itself
- automated coverage proves remote Pi behavior across service/runtime, dedicated remote-network API, iPhone model behavior, and shared structured-presentation seams while protecting existing remote Codex and remote Claude behavior on touched surfaces

## Scope

### In

- remote protocol-native Pi execution on the **Host** through Pi RPC mode
- reuse of the existing provider-neutral remote protocol-native runtime seam inside `NexusService`
- a service-owned single live remote protocol bridge per **Session**
- remote protocol transport over raw SSH stdio without PTY allocation
- **tmux** as the internal durability wrapper for remote protocol-native Pi **Sessions**
- remote Pi **Provider Health** based on remote executable resolution, version detection when possible, Pi RPC startup/readiness checks, light auth-readiness detection where feasible, and other Pi-specific launch prerequisites as needed
- a short-lived direct SSH Pi RPC readiness probe rather than a tmux-backed health probe
- remote Pi default **Session** launch/resume and **Named Session** creation
- full remote Pi **Session Record** lifecycle parity including stop, relaunch, inspect, delete, and **Detach** semantics distinct from stop
- continued Pi linkage storage as generic mutable adapter metadata on the **Session Record**
- preservation of the same Nexus **Session Record** across remote Pi runtime recovery and invalid-linkage fallback
- shared structured macOS **Session** presentation for remote Pi
- full iPhone structured remote Pi support using the existing dedicated **Remote Client** API and shared structured presentation model
- shared app-native **Approval Request** handling for remote Pi through the shared approval model
- reuse of the existing generic structured remote `POST /remote-client/sessions/{sessionID}/input` and approval-decision routes for remote Pi with no Pi-specific remote API
- compatibility-preserving cleanup of Pi-specific structured-surface support gating so supported structured surfaces are governed by shared client rules rather than local-versus-remote Pi branching
- compatibility-preserving propagation of remote Pi structured **Session Surface Support**, **Controller** state, pending **Approval Requests**, and shared structured activity through service, IPC, and dedicated remote API boundaries
- continued use of `prelaunchPrimarySurface` as a shared signal across macOS and iPhone
- test coverage across service, local IPC, shared client models, dedicated remote API, and shared presentation helpers for the remote Pi rollout

### Out

- top-level iOS app target creation or broader iOS productization work
- migration of terminal-backed **Providers** such as Claude onto a structured or protocol-native path
- IBM Bob implementation
- provider-native authentication redesign or new iPhone-specific auth UX
- extra Mac-side confirmation prompts for structured write actions from trusted **Paired Devices**
- a persistent Nexus daemon, agent, or managed helper installation on the **Host**
- a user-facing remote Pi mode switch between structured and terminal execution
- user-facing terminal fallback for remote structured Pi on macOS or iPhone
- automatic in-place reconnect when the live remote Pi bridge drops
- automatic remote runtime reattachment triggered only by opening a **Session** screen
- durable or full structured activity-history backfill after reattaching to a live remote Pi runtime
- user-selectable **Remote Session Strategy**
- broad new workspace-overview or provider-card shortcut actions on iPhone
- broad iPad-first or iPad-specific UX work
- broad **Provider Capability** expansion beyond default-session launch/resume and **Named Session** creation
- new provider configuration UI

## UX minimums

### Workspace overview

- Pi appears in the existing provider-card model on **Remote Workspaces**
- a launchable remote Pi card shows actionable default-**Session** affordance on macOS
- on iPhone, remote Pi no longer appears blocked merely because its primary **Session Surface** is structured
- remote Pi readiness language uses **Host Validation**, **Workspace Availability**, **Provider Health**, **Provider Capability**, and **Session Surface Support** terminology rather than terminal-specific wording

### Provider detail

- remote Pi uses the same provider-detail structure as other **Providers**
- default **Session**, **Named Sessions**, and failed **Session Records** remain in the same product model
- launch and create affordances follow service-owned **Provider Capability**, **Provider Health**, and shared prelaunch surface information
- disabled states use capability reasons for product-support limits, health summaries for readiness limits, and truthful provider-native guidance for auth-blocked states

### Session screen on macOS

- remote Pi uses the shared structured primary **Session Surface** already proven by local Pi, local Codex, and remote Codex
- the structured **Session Surface** is useful without a required terminal fallback
- remote Pi **Approval Requests** appear through the shared app-native approval UI
- touched structured-session copy uses generic shared **Session** language such as prompts, shared activity, **Approval Requests**, reconnect guidance, and restart guidance with provider-aware inserts where helpful

### iPhone Provider detail

- remote Pi keeps using the existing iPhone **Provider detail** shape
- launch and create actions stay in **Provider detail** rather than moving to new overview shortcuts
- if remote Pi is launchable on the active **Paired Mac**, iPhone may use its existing launch and create affordances even though the resulting **Session Surface** is structured
- auth-required states stay blocked with truthful provider-health guidance rather than offering a fake structured auth flow on iPhone

### iPhone Session screen

- remote Pi **Sessions** render as structured/shared activity rather than as terminal emulation
- pending **Approval Requests** are visible on iPhone
- when iPhone is the **Viewer**, structured prompt composer and approval actions remain visible but disabled, with guidance to take **Controller**
- when iPhone is the **Controller**, structured prompt composer and approval actions are enabled
- a successfully launched or created remote Pi **Session** opens immediately on iPhone as a **Viewer** by default
- a failed launch or create opens immediately into failed **Session Record** inspection with relaunch capability
- Stop Session remains visible with confirmation and does not require taking **Controller** first
- remote Pi **Sessions** do not expose a user-facing terminal fallback on iPhone

### iPhone reconnect and recovery

- stale-session reconnect behavior remains the same as the current iPhone structured **Session** model
- reconnect preserves last known content as stale read-only until refresh or observation resumes
- reconnect returns iPhone to **Viewer** status by default
- users explicitly retake **Controller** when they want to resume structured write actions
- relaunch continues to be explicit when a remote Pi **Session Record** is inspectable but not running

## Core rules

- Milestone Twelve is a provider-breadth expansion milestone, not a top-level iOS app-target milestone and not a provider-auth redesign milestone
- Pi becomes a fully launchable protocol-native **Provider** on **Remote Workspaces** in this milestone
- remote Pi uses a structured primary **Session Surface** on both macOS and iPhone
- a **Remote Workspace** still executes on its **Host**; the Mac is the execution authority owner, not the execution target
- remote Pi reuses the existing service-owned SSH stdio bridge plus **tmux** durability model for remote protocol-native **Sessions**
- **tmux** remains the **Remote Session Strategy** for durability across detach, reconnect, and service restart, but it is not the protocol transport and not the product-visible **Session Surface**
- the **Background Service** owns one live remote protocol bridge per **Session**
- attached clients observe the shared Nexus **Session** and must not open their own direct provider bridges to the **Host**
- remote Pi **Provider Health** uses protocol-native readiness rather than terminal-only launch probes
- **Host Validation** keeps ownership of tmux availability; remote Pi **Provider Health** is blocked by failed **Host Validation** rather than treating missing tmux as a Pi-specific misconfiguration
- remote Pi launch and recovery use the resolved absolute executable path from the **Launch Snapshot** rather than re-resolving `pi` from the remote shell each time
- provider-native authentication remains provider-native; explicit remote auth-readiness failure blocks launchability, but mere uncertainty does not
- explicit launch/resume recovers remote structured Pi after **Background Service** restart or bridge loss when possible; passive inspection does not auto-attach it
- if the existing tmux-backed runtime cannot be recovered, relaunch starts a fresh remote runtime and resumes provider-native Pi continuity when possible
- if persisted Pi linkage is invalid, Nexus automatically falls back to a fresh remote Pi session while preserving the same Nexus **Session Record**
- iPhone structured support for remote Pi follows the same shared **Session Surface Support** model as other supported structured **Sessions** on a **Paired Mac**
- **Session Surface Support** remains separate from **Controller** state; surface support answers whether iPhone can present and operate the surface type at all, while **Controller** answers whether this attached client may perform Session-writing actions now
- the **Controller** owns all Session-writing actions, including structured prompts and **Approval Request** decisions
- **Viewer** and **Controller** semantics stay shared across terminal and structured **Session Surfaces**
- launch/create/open/reconnect continue to attach iPhone as a **Viewer** by default
- **Stop Session** and **Delete Session Record** remain separate lifecycle actions with unchanged semantics
- remote Pi stays structured on macOS and iPhone; Nexus does not fake a terminal for it
- durable/full structured activity-history backfill remains out of scope in this milestone
- remote Claude remains terminal-backed and IBM Bob remains non-launchable in this milestone

## Open implementation choices

- exact short-lived remote Pi readiness-probe request shape and startup-success criteria
- exact heuristics for classifying remote Pi auth-required versus auth-uncertain probe outcomes
- exact remote bridge command shape for Pi RPC launch, recovery, and invalid-linkage fallback
- exact shared-model cleanup shape for replacing the current Pi-specific local-versus-remote structured-surface support branch
- exact product copy for remote Pi interrupted recovery, auth-blocked states, and viewer-disabled structured write affordances where Pi-specific inserts may help
- exact touched-seam test matrix and fixture reuse strategy across `Modules/Tests/NexusServiceTests`, `nexusTests/RemotePairingNetworkTests.swift`, `nexusTests/RemoteClientPairingModelTests.swift`, and shared presentation tests
