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

`running -> interrupted` (structured Pi/Codex/IBM Bob) or `running -> broken/exited` (terminal and other surfaces; implementation-specific surfaced reason)

The Session Record survives on disk. Structured sessions reopen on the structured activity feed with persisted history plus an error row explaining that the live runtime was lost. In-flight assistant text that had already streamed into the feed (or provider draft facts/events) is written into persisted structured history on runtime change so it remains visible after restart.

The session remains relaunchable but not reattachable to the prior live runtime.

#### macOS embedded Background Service restarts (milestone one)

On macOS the app bootstraps an embedded Background Service in-process over local XPC (`docs/architecture/ipc.md`). A **new service process** starts when:

- the Nexus app launches or relaunches (fresh bootstrap),
- tests or tools call `NexusEmbeddedServiceBootstrap.bootstrapForTests` / `bootstrap` with a new in-memory service instance, or
- the user explicitly invokes a future `restartService()` IPC action (planned API surface; not a milestone-one seamless reattach path).

Debug rebuilds, crashes, and Instruments profiling can terminate the app or service host and produce the same outcome: Session Records persist, live runtimes do not.

## Deletion and stopping

- `stopSession(sessionID)` affects runtime only.
- `deleteSessionRecord(sessionID)` affects persistence only and is allowed only for non-running sessions.

## Controller/viewer model

Designed-in, even if not fully implemented in milestone one:

- many viewers
- one controller
- explicit controller ownership
