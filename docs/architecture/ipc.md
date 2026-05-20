# Local IPC API

The macOS app talks to the Background Service over real local IPC.

## Principles

- Domain-first, not process-first.
- Service is the source of truth.
- App requests actions in Nexus concepts.
- Terminal streaming is attached separately from CRUD-style requests.

## Milestone one API surface

### Workspace groups

- `listWorkspaceGroups()`
- `createWorkspaceGroup(name)`
- `renameWorkspaceGroup(id, name)`
- `deleteWorkspaceGroup(id)`

### Workspaces

- `listWorkspaces()`
- `getWorkspace(id)`
- `createLocalWorkspace(name?, folderPath, primaryGroupID?)`
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

### Terminal attachment

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

- `terminalOutput`
- `terminalStateChanged`
- `sessionStateChanged`
- `providerHealthChanged`
- `workspaceChanged`
- `diagnosticLogged`

## Non-goals for milestone one

- shared local/network client protocol stability guarantees
- iOS pairing protocol
- remote host and SSH transport APIs
- multi-controller terminal semantics in implementation
