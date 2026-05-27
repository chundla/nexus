# Domain Model

## Entities

### WorkspaceGroup

- `id: WorkspaceGroupID`
- `name: String`
- `sortOrder: Int?`
- `createdAt`
- `updatedAt`

Notes:
- First-class organizer.
- Each workspace has one primary group in V1.

### Workspace

- `id: WorkspaceID`
- `name: String`
- `primaryGroupID: WorkspaceGroupID`
- `kind: .local | .remote`
- `location`
- `lastUsedProviderID: ProviderID?`
- `status: available | unavailable | broken`
- `createdAt`
- `updatedAt`

Location:
- local: absolute path
- remote: host ID + remote path

Notes:
- Stable UUID identity.
- Local and remote locations are separate workspaces.

### Host

- `id: HostID`
- `name: String`
- `sshTarget: String`
- `port: Int?`
- `sshConfigAlias: String?`
- `tmuxAvailable: Bool?`
- `lastValidationAt`
- `validationStatus`

Notes:
- First-class saved remote host profile.
- Multiple remote workspaces may reference one host.

### Provider

Supported V1 set:
- codex
- claude
- ibmBob
- pi

Shared fields:
- `id: ProviderID`
- `displayName`
- `kind`

### ProviderConfig

Layerable config concept with effective resolution order:
1. global defaults
2. host defaults
3. provider defaults
4. workspace overrides
5. session overrides

Key fields:
- executable command/path override
- default args
- shell override
- env overrides
- remote session strategy preference

### ProviderHealth

- `providerID`
- `targetScope`
- `resolvedExecutable`
- `version`
- `launchability`
- `status: available | unavailable | misconfigured | unknown`
- `diagnostics[]`
- `checkedAt`

Minimum contract:
- executable resolution
- version check when possible
- lightweight launchability probe
- structured diagnostics

### Session

- `id: SessionID`
- `workspaceID`
- `providerID`
- `name: String?`
- `isDefault: Bool`
- `state: SessionState`
- `launchSnapshotID`
- `providerNativeLinkage`
- `createdAt`
- `updatedAt`
- `lastAttachedAt`

Notes:
- Default session exists conceptually per workspace+provider.
- Additional named sessions are explicit.
- Failed launches still create session records.
- Provider-native continuation metadata lives on the Session Record as mutable adapter linkage rather than inside the immutable LaunchSnapshot.
- Provider-native thread or conversation identifiers remain linkage metadata rather than public product language.
- Shared Session contracts make the primary Session surface explicit rather than inferring it from Provider identity.

### SessionSurface

- `primaryKind: terminal | structured`
- `secondaryCapabilities[]`

Notes:
- Every Session has one primary SessionSurface.
- The same Provider may expose different SessionSurfaces on different targets or runtimes.

### SessionSurfaceSupport

- `clientKind`
- `canPresentPrimarySurface`
- `canOperatePrimarySurface`
- `reason`

Notes:
- Separate from ProviderCapability.
- Allows a client to inspect a Session it cannot yet fully present or operate.

### SessionStream

Service-owned shared activity model for every Session:
- `sessionID`
- `messages[]`
- `approvalRequests[]`
- `planUpdates[]`
- `diffs[]`
- `commandActivity[]`
- `errors[]`
- `completionState`
- `attachments[]`

Notes:
- Present for every Session regardless of Provider runtime shape or primary SessionSurface.
- Both terminal-backed and protocol-native runtimes project activity into this shared model.

### LaunchSnapshot

- `id: LaunchSnapshotID`
- `workspaceID`
- `providerID`
- `resolvedCommand`
- `resolvedArgs[]`
- `resolvedEnv[]`
- `resolvedWorkingDirectory`
- `executionTarget`
- `remoteSessionStrategy`
- `providerVersionAtLaunch`
- `gitBranchAtLaunch: String?`
- `createdBy`
- `createdAt`

Notes:
- Immutable after session creation.
- Existing sessions do not inherit later config changes.

### TerminalSession

Optional service-owned runtime concept when a Provider exposes a terminal surface:
- `sessionID`
- `pty/process ref`
- `size`
- `boundedScrollback`
- `transcriptPolicy`
- `attachments[]`
- `controllerClientID?`

### ClientAttachment

- `clientID`
- `role: viewer | controller`
- `attachedAt`
- `lastSeenAt`

## Relationships

- WorkspaceGroup 1 -> many Workspaces
- Host 1 -> many remote Workspaces
- Workspace 1 -> many Sessions
- Provider 1 -> many Sessions
- Session 1 -> 1 primary SessionSurface
- Session 1 -> 1 SessionStream
- Session 1 -> 1 LaunchSnapshot
- Session 1 -> 0..1 live TerminalSession
- SessionSurface 1 -> many SessionSurfaceSupport assessments across clients

## Identity and uniqueness

- Workspace canonical identity is internal UUID.
- Workspace location uniqueness is enforced per effective target.
- Default session uniqueness is enforced per workspace+provider.
