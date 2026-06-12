# Milestone Fourteen

## Goal

> **Historical note**
> This document is the newest rollout-planning milestone. For canonical product language use `CONTEXT.md`; for stable architecture use `ARCHITECTURE.md`. The provider matrix in `README.md` summarizes the current checkout.

Prove that Nexus can make IBM Bob a fully launchable structured **Provider** on **Remote Workspaces** by reusing the existing service-owned remote structured **Session** architecture, keeping **tmux** as the **Remote Session Strategy** only while a remote Bob turn is active, and preserving IBM Bob’s on-demand ready-without-runtime lifecycle across macOS and supported iPhone structured **Remote Clients**.

## Rollout status

> **Checkout status:** **Implemented** in this repo — latest milestone in the rollout series.

Milestone Fourteen turns IBM Bob on **Remote Workspaces** into a structured **Provider** path with full **Session Record** lifecycle parity on macOS and supported structured **Remote Client** parity on iPhone. Local IBM Bob keeps its on-demand structured behavior from Milestone Thirteen. Remote Pi and remote Codex remain structured. Claude remains terminal-backed. This milestone does not broaden into Bob-specific approval-product work, terminal fallback, or Host helper installation.

## Success criteria

- user can inspect remote IBM Bob **Provider Health** on a **Remote Workspace** using the existing **Host Validation** -> **Workspace Availability** -> **Provider Health** dependency chain plus Bob-specific passive readiness checks
- user can launch or resume the default remote IBM Bob **Session** for a **Remote Workspace**
- user can create additional remote IBM Bob **Named Sessions**
- remote IBM Bob **Sessions** use the shared structured primary **Session Surface** on macOS and on supported iPhone **Remote Clients** attached to a **Paired Mac**
- remote IBM Bob launch/create opens a ready structured **Session Record** immediately, even before the first prompt creates Bob-native continuity or starts any Host-side Bob process
- the first prompt on a fresh remote IBM Bob **Session** starts Bob on demand on the **Host**, captures Bob-native continuity on the same **Session Record**, and keeps later prompts bound to that same Nexus **Session**
- remote IBM Bob continuity uses the exact stored Bob native session identifier on the **Session Record** rather than `latest`, Host-wide heuristics, or workspace-wide heuristics
- opening an idle remote IBM Bob **Session** passively shows the last persisted structured history and does not auto-launch Bob or auto-attach a remote runtime
- an idle remote IBM Bob **Session** may remain **ready** and inspectable without a continuously attached live remote runtime
- when a remote Bob turn is active, Nexus uses the existing service-owned SSH stdio plus **tmux** remote structured seam for active-turn durability on the **Host**
- after a normal remote Bob turn completes, Nexus preserves the structured history, treats Bob process exit as successful turn completion, tears down the live remote runtime, and leaves the **Session** **ready** for the next prompt
- during an active remote Bob turn, additional prompt submission is rejected until that turn finishes or is stopped
- **Stop Session** interrupts only the active remote Bob turn; after stop, the **Session** stays **ready** for the next prompt
- if partial remote Bob output arrived before stop or interruption, that partial structured history remains visible and persisted
- if the first prompt on a fresh remote Bob **Session** cannot start or resume Bob on the **Host**, the same **Session Record** becomes **failed** and is inspectable with relaunch support
- if a stored Bob native session identifier is invalid on the **Host**, Nexus automatically falls back to a fresh remote Bob conversation on the same **Session Record** and records the continuity reset as a structured status item
- idle remote IBM Bob **Sessions** remain **ready** after **Background Service** restart when their persisted history and Bob-native continuity are still usable; only in-flight interrupted turns become **interrupted**
- if the live remote Bob bridge drops during an active turn, the **Session** becomes inspectable and explicitly recoverable without automatic in-place reconnect
- relaunch returns interrupted or failed remote IBM Bob **Sessions** to a clean **ready** state on the same **Session Record** without auto-replaying the failed prompt
- **Delete Session Record** is allowed when no remote Bob turn is live, even if the Bob **Session** is still **ready** and resumable on demand
- deleting a remote Bob-backed Nexus **Session Record** attempts best-effort Bob-native session deletion on the **Host** when stored Bob-native continuity exists, but Nexus deletion still succeeds if remote Bob-native cleanup cannot be completed safely
- Bob-native sessions created outside Nexus on the **Host** are not auto-imported into Nexus **Session Records**
- IBM Bob does not use shared app-native **Approval Requests** in this milestone
- no persistent Nexus-managed helper installation is required on the **Host** beyond SSH, **tmux**, and IBM Bob itself
- automated coverage proves remote Bob health evaluation, lazy remote launch lifecycle, active-turn durability, persisted partial history, exact-identifier continuity/reset behavior, remote delete cleanup, iPhone structured parity, and stability of existing remote Pi/Codex/Claude behavior on touched seams

## Scope

### In

- remote IBM Bob structured **Session** launchability on **Remote Workspaces**
- reuse of the existing service-owned SSH stdio remote structured **Session** architecture for remote IBM Bob active turns
- **tmux** as the **Remote Session Strategy** only while a remote Bob turn is active
- Bob runtime launch on the **Host** with `-o stream-json --chat-mode advanced --hide-intermediary-output --approval-mode yolo`
- projection of remote Bob `stream-json` events into the shared structured **Session** activity model
- remote IBM Bob default **Session** launch/resume and **Named Session** creation
- exact Bob-native continuity stored as generic mutable adapter metadata on the **Session Record**
- no user-facing exposure of Bob-native identifiers
- lazy remote Bob start on first prompt for fresh **Sessions**
- on-demand remote Bob resume for idle **Sessions** with stored Bob-native continuity
- persisted last-known structured Bob transcript/activity snapshot for idle inspection and restart recovery on remote **Sessions**
- remote IBM Bob **Session Record** lifecycle parity, including inspect, relaunch, stop-turn, and delete behavior adapted to on-demand remote runtime semantics
- iPhone structured support for remote IBM Bob on a **Paired Mac** through the shared structured **Session Surface** model
- compatibility-preserving propagation of remote IBM Bob structured **Session Surface Support**, persisted structured activity, **Controller** state, and turn-driven updates through service, IPC, and dedicated remote API boundaries
- non-destructive remote IBM Bob **Provider Health** using remote executable resolution, version detection when possible, and passive Bob readiness checks such as remote `bob --list-sessions`
- explicit remote Bob setup/auth/license failures that truthfully block launchability
- warning-only diagnostics when remote Bob readiness remains uncertain but not explicitly blocked
- remote IBM Bob turn launch on the **Host** using the resolved absolute Bob executable path from the **Launch Snapshot**
- best-effort Bob-native delete on the **Host** by mapping stored Bob-native continuity to the current remote Bob session list when possible
- test coverage across service/runtime, local IPC, shared client models, dedicated remote API, and shared presentation helpers for the remote IBM Bob rollout

### Out

- Bob-specific terminal fallback on macOS or iPhone
- shared app-native **Approval Request** support for IBM Bob
- Bob-specific instance/team selection UI or automatic `--instance-id` / `--team-id` injection
- automatic `--trust` or `--accept-license` injection
- Bob-specific extra scope via `--include-directories`
- auto-import or adoption of Bob-native sessions that Nexus did not create
- automatic replay of failed prompts during relaunch
- multi-turn queueing while a Bob turn is already active
- user-facing exposure of Bob-native session identifiers
- a Bob-specific remote transport model, PTY fallback, or Host-side Nexus helper/agent installation
- automatic in-place reconnect when the live remote Bob bridge drops
- automatic remote runtime reattachment triggered only by opening a **Session** screen
- durable or full structured activity-history backfill after recovering from an interrupted live remote Bob turn
- user-selectable **Remote Session Strategy**
- new provider configuration UI

## UX minimums

### Workspace overview

- IBM Bob appears in the existing provider-card model on **Remote Workspaces**
- a launchable remote IBM Bob card shows actionable default-**Session** affordance on macOS
- on iPhone, remote IBM Bob does not appear blocked merely because its primary **Session Surface** is structured
- remote IBM Bob readiness language uses **Host Validation**, **Workspace Availability**, **Provider Health**, **Provider Capability**, and **Session Surface Support** terminology rather than terminal wording
- if Bob is blocked by explicit remote license/setup/auth failure, the card shows truthful readiness guidance without Nexus claiming it accepted those prerequisites

### Provider detail

- remote IBM Bob uses the same provider-detail structure as other **Providers**
- default **Session**, **Named Sessions**, and failed **Session Records** remain in the same product model
- launch and create affordances follow service-owned **Provider Capability**, **Provider Health**, and shared prelaunch surface information
- IBM Bob **Named Session** names remain Nexus-owned and are not replaced by Bob-native session titles

### Session screen on macOS

- remote IBM Bob uses the shared structured primary **Session Surface**
- a fresh or relaunched ready remote IBM Bob **Session** shows useful empty-state copy explaining that sending a prompt starts IBM Bob on the **Host**
- opening an idle ready remote IBM Bob **Session** shows persisted structured history without auto-launching Bob
- the composer remains enabled for the current **Controller** on idle ready remote IBM Bob **Sessions** so prompt submission can start/resume Bob on demand
- while a remote Bob turn is active, prompt submission is disabled or rejected with clear busy guidance
- when no remote Bob turn is active, **Stop Session** is hidden or disabled because there is no live runtime to stop
- if a Bob continuity reset succeeds automatically, the feed shows a structured status item rather than an error item
- if a remote Bob turn is stopped or interrupted after partial output, the already-seen structured history remains visible

### iPhone Provider detail

- remote IBM Bob keeps using the existing iPhone **Provider detail** shape
- launch and create actions stay in **Provider detail** rather than moving to new overview shortcuts
- if remote IBM Bob is launchable on the active **Paired Mac**, iPhone may use its existing launch and create affordances even though the resulting **Session Surface** is structured
- auth-required states stay blocked with truthful provider-health guidance rather than offering a fake Bob auth flow on iPhone

### iPhone Session screen

- remote IBM Bob **Sessions** render as structured/shared activity rather than as terminal emulation
- the structured prompt composer is enabled only for the current **Controller**
- launch/create/open/reconnect continue to attach iPhone as a **Viewer** by default
- idle ready remote IBM Bob **Sessions** are inspectable on iPhone from persisted structured history without fake terminal fallback
- iPhone follows the same active-turn busy rules and stop availability rules as macOS
- remote IBM Bob **Sessions** do not expose a user-facing terminal fallback on iPhone

### Restart and recovery

- an idle remote IBM Bob **Session** that was **ready** before **Background Service** restart reopens as **ready** with its persisted structured snapshot when stored Bob-native continuity is still usable
- an in-flight remote IBM Bob turn interrupted by restart becomes **interrupted** with inspectable persisted partial history and explicit relaunch guidance
- if the live remote Bob bridge drops during an active turn, the **Session** becomes inspectable and explicitly recoverable; Nexus does not attempt automatic in-place reconnect
- relaunch returns interrupted or failed remote IBM Bob **Sessions** to **ready** on the same **Session Record** without auto-replaying the failed prompt

## Core rules

- Milestone Fourteen is an IBM Bob provider-breadth milestone, not a Bob-specific approval-product milestone and not a new remote architecture milestone
- IBM Bob becomes a fully launchable structured **Provider** on **Remote Workspaces** in this milestone
- remote IBM Bob uses the shared structured primary **Session Surface** on macOS and supported iPhone **Remote Clients**
- a **Remote Workspace** still executes on its **Host**; the Mac is the execution authority owner, not the execution target
- remote IBM Bob reuses the existing service-owned SSH stdio remote structured **Session** architecture
- **tmux** remains the **Remote Session Strategy** for durability while a remote Bob turn is active, but it is not the protocol transport, not the product-visible **Session Surface**, and not a guarantee that an idle ready remote Bob **Session** keeps a live runtime attached
- remote IBM Bob runs with `-o stream-json --chat-mode advanced --hide-intermediary-output --approval-mode yolo`
- Nexus does not pass `--trust`, `--accept-license`, `--instance-id`, `--team-id`, or `--include-directories` for remote IBM Bob in this milestone
- Nexus never uses `--resume latest` for IBM Bob product flows; it resumes only from the exact stored Bob-native session identifier on the **Session Record**
- Bob-native continuity lives only in generic mutable adapter metadata on the **Session Record** and stays out of product language and UI
- IBM Bob does not expose shared app-native **Approval Requests** in this milestone
- remote IBM Bob **Provider Health** must remain non-destructive and must not create or mutate Bob-native session history
- **Host Validation** keeps ownership of **tmux** availability; remote IBM Bob **Provider Health** is blocked by failed **Host Validation** rather than treating missing **tmux** as a Bob-specific misconfiguration
- explicit Bob license/setup/auth failures block launchability; mere uncertainty may remain launchable with diagnostics
- accepting the IBM Bob license remains an explicit user action outside Nexus
- remote IBM Bob **Sessions** may remain **ready** without a continuously attached live remote runtime when Nexus can still use them now through stored provider-native continuity and persisted history
- opening or inspecting an idle remote IBM Bob **Session** must not auto-launch Bob or auto-attach a remote runtime
- launch/create of a fresh remote IBM Bob **Session** establishes a ready **Session Record** first; the first explicit prompt is the first Bob-native session-creating action on the **Host**
- remote IBM Bob turn launch on the **Host** uses the resolved absolute executable path from the **Launch Snapshot** rather than re-resolving `bob` from the remote shell each turn
- after a successful remote Bob turn completes, Nexus treats Bob process exit as normal completion, tears down the live remote runtime, and leaves the **Session** **ready**
- while an active remote Bob turn is in progress, additional prompt submission is rejected rather than queued
- **Stop Session** affects only an active remote Bob turn; it does not delete Bob-native continuity and does not move an otherwise healthy Bob **Session** out of **ready**
- an idle ready remote IBM Bob **Session** with no live runtime may still be deleted because **Delete Session Record** is tied to live-runtime presence rather than to the top-level **ready** label
- when Bob-native delete cleanup is possible on the **Host**, Nexus attempts it best-effort before deleting the Nexus **Session Record**; if cleanup cannot be completed safely, Nexus still deletes the Nexus record
- Bob-native sessions created outside Nexus are not adopted automatically
- if Bob-native continuity is invalid on the **Host**, Nexus may fall back automatically to a fresh remote Bob conversation on the same **Session Record**; successful fallback is communicated as structured status, not failure
- if the first real remote Bob start on a fresh **Session** fails, that same **Session Record** becomes **failed** and remains inspectable with relaunch support
- explicit relaunch returns failed or interrupted remote IBM Bob **Sessions** to **ready** on the same **Session Record** without auto-replaying the failed prompt
- if the live remote Bob bridge drops during an active turn, the **Session** becomes inspectable and explicitly recoverable; Nexus does not automatically reconnect the in-flight turn in place
- launch/create/open/reconnect continue to attach iPhone as a **Viewer** by default
- **Session Surface Support** remains separate from **Controller** state; surface support answers whether iPhone can present and operate the surface type at all, while **Controller** answers whether this attached client may perform Session-writing actions now
- the shared **Session** remains canonical across clients: idle observers see persisted Bob history, and once any client starts a remote Bob turn all observers receive updates on the same **Session Record**
- no persistent Nexus-managed helper installation is required on the **Host** beyond SSH, **tmux**, and IBM Bob itself

## Open implementation choices

- exact remote IBM Bob active-turn wrapper shape that reuses the shared SSH stdio plus **tmux** seam while treating normal provider exit as successful turn completion
- exact shared remote-runtime bookkeeping changes needed so remote IBM Bob idle readiness is not mistaken for a recoverable continuously attached runtime
- exact passive remote Bob readiness-probe classification for license-not-accepted, auth-required, and ambiguous setup failures
- exact remote best-effort Bob-native delete flow when only remote Bob session-list indexes are deletable
- exact shared copy for remote Bob busy-state guidance, first-prompt empty state, continuity reset status, stop/interruption messaging, and failed-first-prompt inspection
- exact touched-seam test matrix and fixture reuse strategy across service tests, remote-client model tests, network tests, and shared structured presentation tests
