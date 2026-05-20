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
- `providerNativeSessionRef: String?`
- `createdAt`
- `updatedAt`
- `lastAttachedAt`

Notes:
- Default session exists conceptually per workspace+provider.
- Additional named sessions are explicit.
- Failed launches still create session records.

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

Service-owned runtime concept:
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
- Session 1 -> 1 LaunchSnapshot
- Session 1 -> 0..1 live TerminalSession

## Identity and uniqueness

- Workspace canonical identity is internal UUID.
- Workspace location uniqueness is enforced per effective target.
- Default session uniqueness is enforced per workspace+provider.
