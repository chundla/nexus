# Nexus Architecture

Nexus is the workspace-first control center for coding agent CLIs across local and remote environments.

## How to read these docs

- Start with `README.md` for a quick orientation.
- Read `CONTEXT.md` for canonical product language.
- Use this document for the stable high-level architecture.
- Use `docs/architecture/milestone-*.md` for rollout slices; older milestone docs are historical snapshots.
- `docs/architecture/milestone-14.md` is the latest rollout-planning document.
- `docs/prd/nexus-workspace-first-control-center.md` is historical milestone-one product framing, not the source of truth for current rollout details.

## Current documented rollout snapshot

- The multiplatform `nexus` app (macOS + iOS **Remote Client**) and embedded **Background Service** are the primary build targets in this repo.
- Nexus supports terminal-backed and structured (protocol-native and stream-json) **Sessions** behind one shared **Session** model.
- Provider-specific behavior routes through the `ProviderModule` seam (ADR 0034); Claude, Codex, IBM Bob, and Pi each have a dedicated module.
- Milestone Eight established local Pi as the first documented protocol-native structured **Provider** path.
- Milestone Nine generalized structured **Sessions** to local Codex; Milestone Ten to remote Codex.
- Milestone Eleven expanded full structured iPhone **Remote Client** parity for launchable structured **Sessions** on a **Paired Mac**.
- Milestone Twelve added remote Pi as a launchable structured **Provider** with iPhone parity.
- Milestone Thirteen added local IBM Bob as a launchable structured **Provider** (on-demand ready-without-runtime lifecycle).
- Milestone Fourteen is the latest documented plan and adds remote IBM Bob on **Remote Workspaces** with the same on-demand structured lifecycle and iPhone parity.
- Claude remains terminal-backed on all targets; IBM Bob does not use shared app-native **Approval Requests**.

## Product shape

- **Workspace-first**: Workspace is the primary object in the product and domain model.
- **Provider-aware**: Codex, Claude, IBM Bob, and Pi are first-class providers.
- **Session-oriented**: Sessions are provider-managed workstreams within a workspace and provider.
- **Mac-centric execution**: macOS runs the main UI and the **Background Service**; the iOS build is a **Remote Client** to a **Paired Mac** (no independent CLI execution on device).
- **Service-owned orchestration**: The Background Service is the source of truth for state, persistence, provider adapters, and session lifecycle.

## Core domain

- **Workspace Group**: top-level organizer; each workspace has one primary group in V1.
- **Workspace**: a named local or remote working target with stable UUID identity.
- **Provider**: a supported coding CLI integration.
- **Session**: an app-owned provider-managed workstream tied to a workspace and provider.
- **Launch Snapshot**: resolved launch configuration captured at session creation time.
- **Host**: a saved remote SSH host profile.
- **Provider Health**: adapter-reported health and diagnostics for a provider on a target.
- **Session Surface**: the primary product-visible way a Session is presented and interacted with.
- **Session Surface Support**: whether a specific client can present and operate a Session's primary surface.

## Platform model

### macOS

- Hosts the main Nexus UI.
- Hosts the **Background Service**.
- Launches local provider CLIs.
- Later launches remote provider CLIs over SSH.

### iOS

- Ships as the **Remote Client** entry point in the multiplatform `nexus` target (`RemoteClientHomeView`, pairing, structured session UI).
- Attaches to a **Paired Mac** over the dedicated remote network API (ADR 0027); does not run the **Background Service** or local provider CLIs on device.

## System decomposition

### NexusApp

- macOS SwiftUI client.
- Presents workspace-first navigation.
- Talks to the Background Service over real local IPC.
- Does not own authoritative workspace/session/provider state.

### Background Service

Owns:

- persistence
- workspace groups and workspaces
- provider configuration and health
- provider adapters and provider modules
- session lifecycle
- launch snapshot creation
- shared Session streams and presentation state
- terminal session ownership where a Provider exposes a terminal surface
- diagnostics/logging
- later: paired devices and remote client coordination

### Shared modules

- **NexusDomain**: domain entities, identifiers, enums, lifecycle vocabulary.
- **NexusIPC**: local IPC request/response and stream message types.
- **NexusSessionPresentation**: shared structured **Session Presentation** projection consumed by macOS and iOS UI adapters.
- Likely later: **NexusProviders**, **NexusTerminal** (see `docs/architecture/modules.md`).

## Session model

- Each **workspace + provider** has a **default session**.
- Selecting a provider in a workspace reuses the default session by default.
- Users may create additional named sessions explicitly.
- Session launch configuration is snapshotted at creation time.
- Failed launches create inspectable failed session records.
- Nexus may host both terminal-backed and protocol-native Session runtimes behind the same Session model during migration.

### Top-level lifecycle

- configured
- launching
- running
- attentionNeeded
- disconnected
- exited
- broken

Providers and transports may attach substate/diagnostics beneath these shared states.

## Session presentation model

The Background Service owns a canonical shared Session stream for every Session.

Every **Session** has one primary **Session Surface** and may expose additional secondary capabilities. Clients must not infer that surface from **Provider** identity alone.

Shared Session concepts:

- user and assistant messages
- approval requests and decisions
- plan and progress updates
- diffs and file-change proposals
- command activity
- errors and completion state
- attach/detach
- controller/viewer ownership

A Provider may additionally expose presentation-specific surfaces such as:

- terminal input/output/resize and bounded scrollback
- provider-native structured artifacts

Renderers are platform-specific:

- macOS: native Session UI, with terminal rendering when a Provider exposes a terminal surface
- iOS: structured **Session Surface** adapter today (`RemoteClientHomeView`); terminal rendering when a Provider exposes a terminal surface

## Persistence model

Milestone one persistence is **metadata-focused** and service-owned.

Stored:

- workspace groups
- workspaces
- provider config
- provider health snapshots
- sessions
- launch snapshots
- provider-native continuation linkage on Session Records
- persisted structured Session history for structured Session reopen and paging, retained locally for the lifetime of the Session Record unless an explicit reset or replacement flow discards or moves it
- recent/default mappings
- diagnostics metadata

Persisted structured Session history exists to keep bounded live `SessionScreen` behavior separate from reopen and paging needs. It is not an automatic export or full-capture artifact.

Not fully persisted in milestone one:

- live local PTY/process runtime state

If the Background Service restarts, live local sessions are treated as lost and relaunchable.

## Local vs remote

- Local and remote versions of the same project are modeled as **separate workspaces**.
- Remote execution uses **SSH**.
- **tmux** is a session strategy, not a workspace type.
- Remote hosts are first-class saved profiles.
- Nexus reuses the user's existing SSH configuration and does not manage SSH secrets in V1.

## Navigation model

- Top level: workspace groups and workspaces
- Workspace screen: **provider-first** overview
- Provider detail: default session, named sessions, failed sessions, actions
- Focused session screen: provider-appropriate Session presentation, but still owned by workspace/provider
- Quick switch: workspace-first, with provider/session results secondary

## Milestone one

Milestone one proves the service-centered architecture with local-only execution.

### In scope

- macOS app
- embedded Background Service
- real local IPC
- SQLite-backed custom service store
- local workspaces added by folder picker
- workspace groups
- provider cards for all supported providers
- one provider implemented first, chosen by easiest adapter
- default session launch/resume
- additional named sessions
- one main session view with fast switching
- basic global quick switch
- minimal Background Service status area
- minimal diagnostics/log viewer

### Out of scope (milestone one only)

- iOS **Remote Client** product (later milestones; now implemented in the multiplatform app target)
- remote SSH/tmux execution (later milestones; now implemented for structured remote Providers)
- provider installation management
- user-configurable transcript/history retention policy management UI
- multi-client terminal control implementation
- deep provider semantic normalization

## Documents

- `docs/architecture/domain-model.md`
- `docs/architecture/ipc.md`
- `docs/architecture/session-lifecycle.md`
- `docs/architecture/modules.md`
- `docs/architecture/provider-module-deepening.md`
- `docs/architecture/milestone-1.md`
- `docs/architecture/milestone-2.md`
- `docs/architecture/milestone-3.md`
- `docs/architecture/milestone-4.md`
- `docs/architecture/milestone-5.md`
- `docs/architecture/milestone-6.md`
- `docs/architecture/milestone-7.md`
- `docs/architecture/milestone-8.md`
- `docs/architecture/milestone-9.md`
- `docs/architecture/milestone-10.md`
- `docs/architecture/milestone-11.md`
- `docs/architecture/milestone-12.md`
- `docs/architecture/milestone-13.md`
- `docs/architecture/milestone-14.md`
- `docs/adr/`
