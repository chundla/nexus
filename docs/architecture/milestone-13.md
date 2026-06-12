# Milestone Thirteen

## Goal

> **Historical note**
> This document captures the intended scope and decisions for Milestone Thirteen at the time it was written. For current terminology and rollout status, prefer `README.md` (provider matrix), `ARCHITECTURE.md`, and `docs/architecture/milestone-14.md`.

Prove that Nexus can make IBM Bob a fully launchable structured **Provider** on local **Workspaces** by projecting Bob `stream-json` output into the shared structured **Session Surface**, preserving Bob-native continuity on the **Session Record**, and allowing local structured **Sessions** to remain **ready** without a continuously attached provider runtime.

## Rollout status

> **Checkout status:** **Implemented** in this repo. Remote IBM Bob on **Remote Workspaces** shipped in Milestone Fourteen.

Milestone Thirteen turns IBM Bob on local **Workspaces** into a structured **Provider** path with local macOS support and shared iPhone structured **Remote Client** support on a **Paired Mac**. Pi and Codex keep their existing structured behavior, Claude remains terminal-backed, and remote IBM Bob execution remains unsupported in this milestone.

## Success criteria

- user can inspect local IBM Bob **Provider Health** on a local **Workspace** through non-destructive Bob checks that do not create or mutate Bob-native session history
- user can launch or resume the default local IBM Bob **Session** for a **Workspace**
- user can create additional local IBM Bob **Named Sessions**
- IBM Bob **Sessions** use the shared structured primary **Session Surface** on macOS and on supported iPhone **Remote Clients** attached to a **Paired Mac**
- IBM Bob launch/create opens a ready structured **Session Record** immediately, even before the first prompt creates Bob-native continuity
- the first prompt on a fresh IBM Bob **Session** starts Bob on demand, captures Bob-native continuity on the same **Session Record**, and keeps later prompts bound to that same Nexus **Session**
- IBM Bob continuity uses the exact stored Bob native session identifier on the **Session Record** rather than `latest` or workspace-wide heuristics
- opening an idle IBM Bob **Session** passively shows the last persisted structured history and does not auto-launch Bob
- an idle IBM Bob **Session** may remain **ready** and inspectable without a continuously attached live Bob process
- after a normal Bob turn completes, Nexus preserves the structured history, tears down the live Bob runtime, and leaves the **Session** **ready** for the next prompt
- during an active Bob turn, additional prompt submission is rejected until that turn finishes or is stopped
- **Stop Session** interrupts only the active Bob turn; after stop, the **Session** stays **ready** for the next prompt
- if partial Bob output arrived before stop or interruption, that partial structured history remains visible and persisted
- if the first prompt on a fresh Bob **Session** cannot start or resume Bob, the same **Session Record** becomes **failed** and is inspectable with relaunch support
- if a stored Bob native session identifier is invalid, Nexus automatically falls back to a fresh Bob conversation on the same **Session Record** and records the continuity reset as a structured status item
- idle local IBM Bob **Sessions** remain **ready** after **Background Service** restart when their persisted history and Bob-native continuity are still usable; only in-flight interrupted turns become **interrupted**
- **Delete Session Record** is allowed when no Bob turn is live, even if the Bob **Session** is still **ready** and resumable on demand
- deleting a Bob-backed Nexus **Session Record** attempts best-effort Bob-native session deletion when stored Bob-native continuity exists, but Nexus deletion still succeeds if Bob-native cleanup cannot be completed safely
- Bob-native sessions created outside Nexus are not auto-imported into Nexus **Session Records**
- IBM Bob does not use shared app-native **Approval Requests** in this milestone
- automated coverage proves Bob local health evaluation, lazy-start lifecycle, persisted structured history, exact-identifier continuity, relaunch/reset behavior, iPhone structured support, and stability of existing Pi/Codex/Claude behavior on touched seams

## Scope

### In

- local IBM Bob structured **Session** launchability on local **Workspaces**
- Bob runtime launch with `-o stream-json --chat-mode advanced --hide-intermediary-output --approval-mode yolo`
- projection of Bob `stream-json` events into the shared structured **Session** activity model
- local IBM Bob default **Session** launch/resume and **Named Session** creation
- exact Bob-native continuity stored as generic mutable adapter metadata on the **Session Record**
- no user-facing exposure of Bob-native identifiers
- lazy Bob start on first prompt for fresh **Sessions**
- on-demand Bob resume for idle **Sessions** with stored Bob-native continuity
- persisted last-known structured Bob transcript/activity snapshot for idle inspection and restart recovery
- local IBM Bob **Session Record** lifecycle parity, including inspect, relaunch, stop-turn, and delete behavior adapted to on-demand runtime semantics
- iPhone structured support for local IBM Bob on a **Paired Mac** through the shared structured **Session Surface** model
- compatibility-preserving propagation of IBM Bob structured **Session Surface Support**, persisted structured activity, **Controller** state, and turn-driven updates through service, IPC, and dedicated remote API boundaries
- non-destructive local IBM Bob **Provider Health** using executable resolution, version detection when possible, and passive Bob readiness checks such as `bob --list-sessions`
- explicit Bob setup/auth/license failures that truthfully block launchability
- warning-only diagnostics when Bob readiness remains uncertain but not explicitly blocked
- best-effort Bob-native delete by mapping stored Bob-native continuity to the current Bob session list when possible
- test coverage across service/runtime, local IPC, shared client models, dedicated remote API, and shared presentation helpers for the IBM Bob rollout

### Out

- remote IBM Bob execution on **Remote Workspaces**
- shared app-native **Approval Request** support for IBM Bob
- Bob-specific terminal fallback on macOS or iPhone
- Bob-specific instance/team selection UI or automatic `--instance-id` / `--team-id` injection
- automatic `--trust` or `--accept-license` injection
- Bob-specific extra scope via `--include-directories`
- auto-import or adoption of Bob-native sessions that Nexus did not create
- automatic replay of failed prompts during relaunch
- multi-turn queueing while a Bob turn is already active
- user-facing exposure of Bob-native session identifiers
- remote IBM Bob productization, SSH/tmux work, or Host-specific IBM Bob behavior
- new provider configuration UI

## UX minimums

### Workspace overview

- IBM Bob appears in the existing provider-card model on local **Workspaces**
- a launchable local IBM Bob card shows actionable default-**Session** affordance
- local IBM Bob readiness language uses **Provider Health** and **Provider Capability** terminology rather than terminal wording
- if Bob is blocked by explicit license/setup/auth failure, the card shows truthful readiness guidance without Nexus claiming it accepted those prerequisites

### Provider detail

- local IBM Bob uses the same provider-detail structure as other **Providers**
- default **Session**, **Named Sessions**, and failed **Session Records** remain in the same product model
- launch and create affordances follow service-owned **Provider Capability** and **Provider Health**
- IBM Bob **Named Session** names remain Nexus-owned and are not replaced by Bob-native session titles

### Session screen on macOS

- IBM Bob uses the shared structured primary **Session Surface**
- a fresh or relaunched ready IBM Bob **Session** shows useful empty-state copy explaining that sending a prompt starts the IBM Bob **Session**
- opening an idle ready IBM Bob **Session** shows persisted structured history without auto-launching Bob
- the composer remains enabled for the current **Controller** on idle ready IBM Bob **Sessions** so prompt submission can start/resume Bob on demand
- while a Bob turn is active, prompt submission is disabled or rejected with clear busy guidance
- when no Bob turn is active, **Stop Session** is hidden or disabled because there is no live runtime to stop
- if a Bob continuity reset succeeds automatically, the feed shows a structured status item rather than an error item
- if a Bob turn is stopped or interrupted after partial output, the already-seen structured history remains visible

### iPhone Remote Client

- iPhone can launch, create, inspect, relaunch, and operate local structured IBM Bob **Sessions** on a **Paired Mac** through the shared structured **Session Surface** model
- launch/create/open/reconnect continue to attach iPhone as a **Viewer** by default
- the structured prompt composer is enabled only for the current **Controller**
- idle ready IBM Bob **Sessions** are inspectable on iPhone from persisted structured history without fake terminal fallback
- iPhone follows the same active-turn busy rules and stop availability rules as macOS

### Restart and recovery

- an idle IBM Bob **Session** that was **ready** before **Background Service** restart reopens as **ready** with its persisted structured snapshot when stored Bob-native continuity is still usable
- an in-flight IBM Bob turn interrupted by restart becomes **interrupted** with inspectable persisted partial history and explicit relaunch guidance
- relaunch returns interrupted or failed IBM Bob **Sessions** to a clean **ready** state on the same **Session Record** without auto-replaying the failed prompt

## Core rules

- Milestone Thirteen is an IBM Bob provider-breadth milestone, not a remote IBM Bob milestone and not a Bob-specific approval-product milestone
- IBM Bob is local-only in this milestone
- IBM Bob uses the shared structured primary **Session Surface** on macOS and supported iPhone **Remote Clients**
- IBM Bob runs with `-o stream-json --chat-mode advanced --hide-intermediary-output --approval-mode yolo`
- Nexus does not pass `--trust`, `--accept-license`, `--instance-id`, `--team-id`, or `--include-directories` for IBM Bob in this milestone
- Nexus never uses `--resume latest` for IBM Bob product flows; it resumes only from the exact stored Bob-native session identifier on the **Session Record**
- Bob-native continuity lives only in generic mutable adapter metadata on the **Session Record** and stays out of product language and UI
- IBM Bob does not expose shared app-native **Approval Requests** in this milestone
- IBM Bob **Provider Health** must remain non-destructive and must not create or mutate Bob-native session history
- explicit Bob license/setup/auth failures block launchability; mere uncertainty may remain launchable with diagnostics
- accepting the IBM Bob license remains an explicit user action outside Nexus
- IBM Bob **Sessions** may remain **ready** without a continuously attached provider runtime when Nexus can still use them now through stored provider-native continuity
- opening or inspecting an idle IBM Bob **Session** must not auto-launch Bob
- the first explicit prompt is the first Bob-native session-creating action for a fresh IBM Bob **Session**
- after a successful Bob turn completes, Nexus tears down the live Bob runtime and leaves the **Session** **ready**
- while an active Bob turn is in progress, additional prompt submission is rejected rather than queued
- **Stop Session** affects only an active Bob turn; it does not delete Bob-native continuity and does not move an otherwise healthy Bob **Session** out of **ready**
- an idle ready IBM Bob **Session** with no live runtime may still be deleted because **Delete Session Record** is tied to live-runtime presence rather than to the top-level **ready** label
- when Bob-native delete cleanup is possible, Nexus attempts it best-effort before deleting the Nexus **Session Record**; if cleanup cannot be completed safely, Nexus still deletes the Nexus record
- Bob-native sessions created outside Nexus are not adopted automatically
- if Bob-native continuity is invalid, Nexus may fall back automatically to a fresh Bob conversation on the same **Session Record**; successful fallback is communicated as structured status, not failure
- if the first real Bob start on a fresh **Session** fails, that same **Session Record** becomes **failed** and remains inspectable with relaunch support
- relaunch returns failed or interrupted IBM Bob **Sessions** to **ready** on the same **Session Record** without auto-replaying the failed prompt
- the shared **Session** remains canonical across clients: idle observers see persisted Bob history, and once any client starts a Bob turn all observers receive updates on the same **Session Record**

## Open implementation choices

- exact local IBM Bob runtime wrapper shape for on-demand per-turn launch, resume, and teardown
- exact adapter metadata keys used to store Bob-native session continuity on the **Session Record**
- exact persisted structured-history snapshot shape for idle Bob **Sessions** and restart recovery
- exact heuristics for mapping Bob `tool_use` and `tool_result` events into shared **message**, **command**, **diff**, **completion**, **status**, and **error** activity items
- exact passive Bob readiness probe classification for license-not-accepted, auth-required, and ambiguous setup failures
- exact best-effort Bob-native delete flow when only Bob session-list indexes are deletable
- exact shared copy for Bob busy-state guidance, first-prompt empty state, continuity reset status, stop/interruption messaging, and failed-first-prompt inspection
- exact touched-seam test matrix and fixture reuse strategy across service tests, remote-client model tests, network tests, and shared structured presentation tests
