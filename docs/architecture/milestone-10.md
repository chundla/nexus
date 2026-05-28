# Milestone Ten

## Goal

Prove that Nexus can run a protocol-native **Codex Session** on a **Remote Workspace** by extending the shared **Session** architecture to remote execution, keeping **tmux** as the **Remote Session Strategy** for durability, and presenting remote Codex through the same structured primary **Session Surface** on macOS as local Codex.

## Rollout status

Milestone Ten turns Codex on **Remote Workspaces** into a protocol-native **Provider** path with a structured primary **Session Surface** on macOS. Local Codex stays protocol-native and structured from Milestone Nine. Remote Claude stays terminal-backed, remote Pi remains unsupported, and iPhone can inspect remote structured Codex **Sessions** on a **Paired Mac** but cannot launch, create, or control them in this milestone.

## Success criteria

- user can inspect remote Codex **Provider Health** on a **Remote Workspace** using the existing **Host Validation** -> **Workspace Availability** -> **Provider Health** dependency chain plus Codex-specific protocol-native readiness checks
- user can launch or resume the default remote Codex **Session** for a **Remote Workspace**
- user can create additional remote Codex **Named Sessions**
- remote Codex **Session Records** follow the same stop, relaunch, inspect, and delete rules as existing remote **Session Records**
- existing remote terminal-backed Codex **Session Records** remain valid and relaunch through the new remote protocol-native Codex runtime without recreation
- macOS renders remote Codex through the shared structured primary **Session Surface** rather than a terminal surface
- remote Codex can emit app-native **Approval Requests** and macOS can approve or deny them through the shared Nexus approval flow
- the **Background Service** owns one live remote protocol bridge per remote Codex **Session**, and attached clients observe the shared Nexus **Session** rather than opening their own Host connections
- remote protocol-native Codex runs on the **Host** rather than on the Mac, using a provider-neutral remote protocol-native runtime seam inside the **Background Service**
- **tmux** remains the **Remote Session Strategy** for remote Codex durability, but it is not the protocol transport and not the product-visible **Session Surface**
- the remote protocol bridge uses raw SSH stdio without PTY allocation, while existing terminal-backed remote **Providers** keep their PTY-oriented transport
- remote Codex launch and recovery use the resolved absolute remote executable path captured in the **Launch Snapshot**
- tmux-backed remote Codex runtime remains recoverable after **Background Service** restart through explicit launch/resume, while simply inspecting the **Session Record** does not auto-reattach it
- if a known tmux-backed remote runtime is gone, relaunch starts a fresh remote runtime and resumes the persisted Codex thread linkage when valid
- if persisted Codex thread linkage is invalid, Nexus automatically falls back to a fresh remote Codex thread while preserving the same Nexus **Session Record**
- if the live remote protocol bridge drops while the remote runtime still exists, the **Session** becomes inspectable and explicitly recoverable without requiring automatic in-place reconnect on macOS
- iPhone can browse and inspect remote structured Codex **Session Records** on a **Paired Mac**, shows explicit unsupported-**Session Surface** guidance, and does not fake a terminal for those **Sessions**
- iPhone disables launch, create, approval, and control actions that would require operating remote Codex’s unsupported primary **Session Surface**, while still showing truthful Mac-owned **Provider Health**
- no persistent Nexus helper installation is required on the **Host** beyond SSH, **tmux**, and Codex itself
- automated coverage proves remote protocol-native Codex behavior, remote recovery semantics, iPhone unsupported-surface handling, and existing remote Claude stability on touched seams

## Scope

### In

- a provider-neutral remote protocol-native runtime seam inside `NexusService`
- a service-owned single live remote protocol bridge per **Session**
- remote protocol transport over raw SSH stdio without PTY allocation
- **tmux** as the internal durability wrapper for remote protocol-native **Sessions**
- remote Codex execution on the **Host** through `codex app-server`
- remote Codex **Provider Health** based on remote executable resolution, version detection when possible, protocol startup or handshake readiness, light auth-readiness detection where feasible, and other Codex-specific launch prerequisites as needed
- a short-lived direct SSH protocol handshake for remote Codex readiness checks rather than a tmux-backed health probe
- remote Codex default **Session** launch/resume and **Named Session** creation
- full remote Codex **Session Record** lifecycle parity including stop, relaunch, inspect, delete, and **Detach** semantics distinct from stop
- generic service-owned remote runtime recovery linkage separate from provider-native adapter metadata
- continued Codex thread linkage storage as generic mutable adapter metadata on the **Session Record**
- preservation of remote Codex **Session Record** identity across the migration from terminal-backed remote Codex to protocol-native remote Codex
- provider-general structured macOS **Session** presentation shared by Pi and Codex
- shared app-native **Approval Request** handling for remote protocol-native Codex through the shared approval model
- compatibility-preserving propagation of remote Codex structured **Session Surface** and unsupported-surface state through local IPC and the dedicated **Remote Client** API
- service-owned prelaunch primary-**Session Surface** prediction, or equivalent shared signal, so clients can disable actions that would create unsupported surfaces before a **Session** exists
- explicit unsupported-surface handling on iPhone for remote structured Codex **Sessions** encountered on a **Paired Mac**
- automated coverage across service, local IPC, shared client models, and dedicated **Remote Client** boundaries for the remote Codex rollout

### Out

- iPhone structured Codex rendering, structured Codex control, or **Approval Request** handling
- a user-facing remote Codex mode switch between terminal-backed and protocol-native execution
- automatic in-place macOS reconnect when the live remote protocol bridge drops
- full structured activity-history backfill after reattaching to a live remote Codex runtime
- a persistent Nexus daemon, agent, or managed helper installation on the **Host**
- remote protocol-native Pi execution on **Remote Workspaces**
- migration of remote Claude onto a protocol-native runtime
- IBM Bob implementation
- new provider configuration UI
- user-selectable **Remote Session Strategy**
- broad **Provider Capability** expansion beyond default-session launch/resume and **Named Session** creation, except for the minimum shared signal needed to predict unsupported primary surfaces before launch
- automatic remote runtime reattachment triggered only by opening a **Session** screen
- a user-facing terminal fallback for remote structured Codex on macOS

## UX minimums

### Workspace overview

- Codex appears in the existing provider-card model on **Remote Workspaces**
- a launchable remote Codex card shows actionable default-**Session** affordance on macOS
- remote Codex readiness language uses **Host Validation**, **Workspace Availability**, **Provider Health**, and **Provider Capability** terminology rather than terminal-specific wording
- touched shared overview surfaces no longer imply that remote Codex is terminal-backed

### Provider detail

- remote Codex uses the same provider-detail structure as other **Providers**
- default **Session**, **Named Sessions**, and failed **Session Records** remain in the same product model
- launch and create affordances follow service-owned **Provider Capability** plus service-owned prelaunch surface information
- disabled actions continue to use capability reasons for product-support limits, health summaries for readiness limits, and unsupported-surface guidance for client limits

### Session screen on macOS

- remote Codex uses the shared structured primary **Session Surface** already proven by local Pi and local Codex
- the structured **Session Surface** is useful without a required terminal fallback
- remote Codex **Approval Requests** appear through the shared app-native approval UI
- touched macOS structured-session chrome uses generic language such as shared activity, prompts, connection state, detach/reconnect guidance, and restart guidance with provider-aware inserts where helpful

### iPhone Remote Client

- iPhone can browse remote structured Codex **Sessions** on a **Paired Mac** rather than having them hidden
- iPhone shows explicit unsupported-**Session Surface** guidance for remote structured Codex **Sessions** instead of pretending they are terminal **Sessions**
- iPhone disables launch, create, approval, and control actions that would require operating remote Codex’s unsupported primary **Session Surface**
- iPhone still shows truthful Mac-owned Codex **Provider Health** for the **Workspace Target** even when this client cannot operate the resulting **Session Surface**

## Core rules

- Milestone Ten is a remote protocol-native **Session** expansion milestone, not a broad remote-client capability milestone
- Codex is the only new remote protocol-native fully **Launchable Provider** in this milestone
- Codex uses a protocol-native structured primary **Session Surface** on both local and remote macOS paths
- remote Codex replaces the previous remote terminal-backed Codex path; there is no user-facing remote mode choice in this milestone
- a **Remote Workspace** still executes on its **Host**; the Mac is the execution authority owner, not the execution target
- **tmux** remains the **Remote Session Strategy** for durability across detach, reconnect, and service restart, but it is not the protocol transport and not the product-visible **Session Surface**
- remote protocol transport for structured Codex uses raw SSH stdio without PTY allocation
- the **Background Service** owns one live remote protocol bridge per **Session**
- attached clients observe the shared Nexus **Session** and must not open their own direct provider bridges to the **Host**
- remote Codex **Provider Health** uses protocol-native readiness rather than terminal-only launch probes
- **Host Validation** keeps ownership of tmux availability; remote Codex **Provider Health** is blocked by failed **Host Validation** rather than treating missing tmux as a Codex-specific misconfiguration
- remote Codex launch and recovery use the resolved absolute executable path from the **Launch Snapshot** rather than re-resolving `codex` from the remote shell each time
- provider-native authentication remains provider-native; explicit remote auth-readiness failure blocks launchability, but mere uncertainty does not
- explicit launch/resume recovers remote structured Codex after **Background Service** restart or bridge loss when possible; passive inspection does not auto-attach it
- if the existing tmux-backed runtime cannot be recovered, relaunch starts a fresh remote runtime and resumes provider-native Codex continuity when possible
- if persisted Codex thread linkage is invalid, Nexus automatically falls back to a fresh remote thread while preserving the same Nexus **Session Record**
- full structured activity-history backfill is not required in this milestone when reattaching to a live remote runtime
- iPhone keeps remote structured Codex **Sessions** visible and inspectable but unsupported
- **Provider Health** and **Provider Capability** remain Mac-truthful for the **Workspace Target**; iPhone action gating comes from client-specific unsupported-surface state rather than rewriting provider launchability
- remote Claude remains terminal-backed, remote Pi remains unsupported, and IBM Bob remains non-launchable in this milestone

## Open implementation choices

- exact remote bridge command shape and rendezvous mechanism used to reconnect the service-owned bridge to the tmux-backed remote Codex runtime
- exact generic persistence shape for service-owned remote runtime recovery linkage
- exact shared-model shape for prelaunch primary-**Session Surface** prediction and unsupported-surface action gating
- exact product copy for interrupted remote structured Codex recovery, detach guidance, and unsupported-surface explanations on iPhone
- exact compatibility-preserving changes needed at local IPC and dedicated **Remote Client** API boundaries to carry the new prelaunch surface signal
