# Nexus Architecture

Nexus is the workspace-first control center for coding agent CLIs across local and remote environments.

## Product shape

- **Workspace-first**: Workspace is the primary object in the product and domain model.
- **Provider-aware**: Codex, Claude, IBM Bob, and Pi are first-class providers.
- **Session-oriented**: Sessions are managed within a workspace and provider.
- **Mac-centric execution**: macOS runs the UI and the Background Service; iOS later acts as a remote client.
- **Service-owned orchestration**: The Background Service is the source of truth for state, persistence, provider adapters, and session lifecycle.

## Core domain

- **Workspace Group**: top-level organizer; each workspace has one primary group in V1.
- **Workspace**: a named local or remote working target with stable UUID identity.
- **Provider**: a supported coding CLI integration.
- **Session**: an app-owned session tied to a workspace and provider.
- **Launch Snapshot**: resolved launch configuration captured at session creation time.
- **Host**: a saved remote SSH host profile.
- **Provider Health**: adapter-reported health and diagnostics for a provider on a target.

## Platform model

### macOS

- Hosts the main Nexus UI.
- Hosts the **Background Service**.
- Launches local provider CLIs.
- Later launches remote provider CLIs over SSH.

### iOS

- Not part of milestone one.
- Will act as a remote client to the macOS Background Service.
- Will not independently execute local coding CLIs.

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
- provider adapters
- session lifecycle
- launch snapshot creation
- terminal session ownership
- diagnostics/logging
- later: paired devices and remote client coordination

### Shared modules

- **NexusDomain**: domain entities, identifiers, enums, lifecycle vocabulary.
- **NexusIPC**: local IPC request/response and stream message types.
- Later: **NexusProviders**, **NexusTerminal**.

## Session model

- Each **workspace + provider** has a **default session**.
- Selecting a provider in a workspace reuses the default session by default.
- Users may create additional named sessions explicitly.
- Session launch configuration is snapshotted at creation time.
- Failed launches create inspectable failed session records.

### Top-level lifecycle

- configured
- launching
- running
- attentionNeeded
- disconnected
- exited
- broken

Providers and transports may attach substate/diagnostics beneath these shared states.

## Terminal model

The Background Service owns canonical terminal session state.

Shared terminal concepts:

- input
- output
- resize
- bounded scrollback
- attach/detach
- transcript capture policy
- controller/viewer ownership

Renderers are platform-specific:

- macOS: embedded terminal component
- iOS: later remote renderer

## Persistence model

Milestone one persistence is **metadata-focused** and service-owned.

Stored:

- workspace groups
- workspaces
- provider config
- provider health snapshots
- sessions
- launch snapshots
- recent/default mappings
- diagnostics metadata

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
- Provider detail: default session, alternate sessions, failed sessions, actions
- Focused session screen: terminal-first, but still owned by workspace/provider
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

### Out of scope

- iOS app target and implementation
- remote SSH/tmux execution
- provider installation management
- full transcript retention policy management
- multi-client terminal control implementation
- deep provider semantic normalization

## Documents

- `docs/architecture/domain-model.md`
- `docs/architecture/ipc.md`
- `docs/architecture/session-lifecycle.md`
- `docs/architecture/modules.md`
- `docs/architecture/milestone-1.md`
- `docs/architecture/milestone-2.md`
- `docs/architecture/milestone-3.md`
- `docs/adr/`
