# Session Lifecycle

## Top-level states

- `configured`
- `launching`
- `running`
- `attentionNeeded`
- `disconnected`
- `exited`
- `broken`

These are app-level states shared across providers. Providers and transports may add substate details and diagnostics.

## Core rules

1. Each workspace+provider has a default session path.
2. Selecting a provider in a workspace reuses the default session by default.
3. Additional sessions must be created explicitly.
4. Launch config is snapshotted at session creation time.
5. Failed launches still create inspectable failed session records.
6. Stop Session and Delete Record are separate actions.

## Typical transitions

### Default launch

`configured -> launching -> running`

### Launch failure

`configured -> launching -> broken`

The broken session remains inspectable and relaunchable.

### Normal exit

`running -> exited`

### Attention-needed path

`running -> attentionNeeded -> running`

### Service restart in milestone one

For live local sessions, service restart does not restore runtime attachment:

`running -> broken` or `running -> exited/lost` (implementation-specific surfaced reason)

The session remains relaunchable but not reattachable.

## Deletion and stopping

- `stopSession(sessionID)` affects runtime only.
- `deleteSessionRecord(sessionID)` affects persistence only and is allowed only for non-running sessions.

## Controller/viewer model

Designed-in, even if not fully implemented in milestone one:

- many viewers
- one controller
- explicit controller ownership
