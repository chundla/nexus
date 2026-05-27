# Milestone Eight

## Goal

Prove that protocol-native integrations make Nexus materially better by shipping Pi as the first local protocol-native **Launchable Provider**, introducing a shared Session stream and structured Session UI while keeping existing terminal-backed Providers stable.

## Rollout status

Milestone Eight introduces the provider-general protocol-native Session seam. Pi becomes a local **Launchable Provider** on local **Workspaces** only. Claude and current Codex remain launchable through their existing terminal-backed runtimes during this milestone. **Remote Workspaces** and **Remote Clients** do not use protocol-native Session runtimes yet.

## Success criteria

- user can inspect local Pi **Provider Health** on a local **Workspace**
- user can launch or resume the default local Pi **Session** for a **Workspace**
- user can create additional local Pi **Named Sessions**
- Pi **Session Records** follow the same stop, relaunch, inspect, and delete rules as existing local **Session Records**
- the **Background Service** exposes a shared Session stream for messages, **Approval Requests**, progress, diffs, command activity, errors, and completion state
- macOS renders a Pi **Session** with structured Session UI rather than a faux terminal-first transcript
- macOS can approve or deny Pi **Approval Requests** through app-native UI
- shared Nexus models and local IPC support both terminal-backed and protocol-native Session runtimes at the same time
- Claude and Codex continue to work through the existing terminal-backed runtime path without product regression on touched surfaces
- local Pi runtime loss after **Background Service** restart is understandable, inspectable, and relaunchable rather than silently restored
- automated coverage proves Pi local launch/resume, structured Session behavior, and approval flows while protecting Claude/Codex regression surfaces

## Scope

### In

- a service-owned shared Session stream inside `NexusService`
- an internal Session runtime seam that supports both terminal-backed and protocol-native runtimes
- a local Pi adapter that uses Pi RPC mode rather than terminal-driving Pi
- local Pi **Provider Health** based on runtime availability, auth readiness, protocol handshake readiness, and other Pi launch prerequisites as needed
- local Pi default **Session** launch/resume and **Named Session** creation
- provider-native Pi session identifiers stored as adapter linkage metadata on the **Session Record**
- shared **Approval Request** modeling and app-native approval decisions for Pi
- structured macOS Session presentation for protocol-native Sessions
- local IPC additions required to drive structured Pi Sessions on macOS
- provider-aware shared copy on touched Session surfaces
- automated coverage for Pi plus regression coverage for existing terminal-backed Providers

### Out

- Codex app-server implementation
- migration of Claude or current Codex onto protocol-native runtimes
- remote Pi execution on **Remote Workspaces**
- dedicated **Remote Client** API or iPhone structured Session support for Pi
- automatic recovery or reattachment of a live local protocol-native **Session** across **Background Service** restart
- replacement of terminal presentation for terminal-backed Providers
- provider auth management beyond provider-native auth and readiness diagnostics
- broad **Provider Capability** expansion beyond default-session launch/resume and **Named Session** creation
- remote SSH/tmux contract changes
- new provider configuration UI

## UX minimums

### Workspace overview

- Pi appears in the existing provider-card model as a local **Launchable Provider** when ready
- a launchable Pi card shows actionable default-session affordance
- an unavailable Pi action explains itself through **Provider Health** and **Provider Capability** language rather than terminal-specific copy

### Provider detail

- Pi uses the same provider-detail structure as other Providers
- default **Session**, **Named Sessions**, and failed **Session Records** remain in the same product model
- launch and create affordances follow service-owned **Provider Capability** state

### Session screen

- a Pi **Session** renders structured messages, **Approval Requests**, progress, diffs, command activity, errors, and completion state
- a Pi **Session** does not require a faux terminal surface to be useful
- Claude and Codex keep their existing terminal presentation during the milestone

## Core rules

- Milestone Eight is a protocol-native Session architecture and UX milestone, not a remote-expansion milestone
- Pi is the only new protocol-native fully **Launchable Provider** in this milestone
- Pi is local-only in this milestone
- a **Session** remains the public Nexus concept; provider-native words like thread or conversation stay adapter-internal
- the shared Session stream is service-owned and canonical; terminal is an optional Session surface
- **Approval Request** is a shared Session concept; provider authentication remains provider-native
- the **Background Service** may host terminal-backed and protocol-native runtimes side-by-side during migration
- local protocol-native runtime is not restored after **Background Service** restart in this milestone
- **Provider Health** continues to answer whether Nexus can launch a **Session** now, even when readiness comes from protocol or auth checks rather than executable probes
- existing **Workspace**, **Provider**, **Session**, and **Session Record** language stays unchanged

## Open implementation choices

- exact shared Session event taxonomy and payload shape
- exact local IPC stream shape for structured Sessions
- exact structured macOS Session layout for Pi
- exact boundary between shared Session events and provider-specific extension payloads
- exact Pi **Provider Health** diagnostics copy
- exact minimal launch-snapshot expansion needed for protocol-native runtimes
