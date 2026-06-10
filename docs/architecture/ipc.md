# Local IPC API

The macOS app talks to the Background Service over real local IPC.

## Principles

- Domain-first, not process-first.
- Service is the source of truth.
- App requests actions in Nexus concepts.
- Terminal streaming is attached separately from CRUD-style requests.

## Current milestone-one bootstrap

The current bootstrap path is implemented and exercised end-to-end:

- the macOS app bootstraps an embedded Background Service session at launch
- the app connects over real local `NSXPCConnection` / `NSXPCListener`
- the bootstrap uses an anonymous listener endpoint owned by the embedded service session
- shared domain payloads are serialized across the XPC boundary as `Data`
- `getServiceStatus()` proves service reachability and store ownership
- `listWorkspaceGroups()` / `createWorkspaceGroup(name)` are live on the boundary
- `listWorkspaces()` / `createLocalWorkspace(name?, folderPath, primaryGroupID?)` are live on the boundary

### When the embedded service restarts

Milestone one does **not** reattach live local session runtimes after a restart. Session Records and structured history files owned by the service survive on disk; only in-memory runtimes are lost.

Expect a restart (new bootstrap instance) when the Nexus app starts again, when a debug build replaces the running app, when the process crashes, or when tests construct a fresh `NexusEmbeddedServiceBootstrap` service against the same `rootURL` to simulate reopening persistence.

Structured Pi/Codex/IBM Bob sessions surface `interrupted` with relaunch-oriented copy. See `docs/architecture/session-lifecycle.md` for state transitions and persistence behavior during in-flight turns.

## Milestone one API surface

### Workspace groups

Live now:
- `listWorkspaceGroups()`
- `createWorkspaceGroup(name)`

Planned:
- `renameWorkspaceGroup(id, name)`
- `deleteWorkspaceGroup(id)`

### Workspaces

Live now:
- `listWorkspaces()`
- `createLocalWorkspace(name?, folderPath, primaryGroupID?)`

Planned:
- `getWorkspace(id)`
- `updateWorkspace(id, ...)`
- `reassignWorkspaceGroup(workspaceID, groupID)`
- `deleteWorkspace(id)`
- `validateWorkspace(id)`

### Providers

- `listSupportedProviders()`
- `listProviderHealth(workspaceID)`
- `refreshProviderHealth(workspaceID, providerID?)`
- `getProviderConfigurationScope(...)`
- `updateProviderConfigurationScope(...)`

### Sessions

- `listSessions(workspaceID, providerID?)`
- `getSession(id)`
- `launchDefaultSession(workspaceID, providerID)`
- `resumeDefaultSession(workspaceID, providerID)`
- `createAdditionalSession(workspaceID, providerID, name?, overrides?)`
- `stopSession(sessionID)`
- `deleteSessionRecord(sessionID)`
- `relaunchSession(sessionID)`
- `observeSession(sessionID)`
- `respondToApprovalRequest(sessionID, approvalRequestID, decision)`

### Optional terminal attachment

Used only when a Provider exposes a terminal surface.

- `attachTerminal(sessionID, clientMetadata)`
- `detachTerminal(sessionID, clientID)`
- stream input events
- stream output events
- stream resize events
- stream lifecycle events

### Diagnostics and service state

- `getServiceStatus()`
- `restartService()`
- `listDiagnostics(limit, level?)`

## Stream event families

- `sessionMessage`
- `sessionApprovalChanged`
- `sessionProgressChanged`
- `sessionDiffChanged`
- `sessionCommandActivityChanged`
- `sessionStateChanged`
- `terminalOutput`
- `terminalStateChanged`
- `providerHealthChanged`
- `workspaceChanged`
- `diagnosticLogged`

## Non-goals for milestone one

- shared local/network client protocol stability guarantees
- iOS pairing protocol
- remote host and SSH transport APIs
- multi-controller terminal semantics in implementation
