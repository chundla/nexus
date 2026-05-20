# Module and Target Boundaries

## Immediate target split

### NexusApp

Responsibilities:
- macOS UI
- workspace-first navigation
- provider cards and provider detail screens
- session terminal screen
- quick switch UI
- minimal diagnostics and service status UI
- local IPC client

Must not own:
- authoritative session lifecycle
- provider adapter logic
- persistence
- PTY/process orchestration

### NexusService

Responsibilities:
- Background Service runtime
- authoritative state and persistence
- provider adapters
- health checks
- launch snapshot resolution
- session lifecycle orchestration
- PTY/process ownership
- diagnostics

### NexusDomain

Responsibilities:
- identifiers
- core entities
- enums/state machines
- value objects
- shared vocabulary

### NexusIPC

Responsibilities:
- request/response models
- stream event models
- attachment/event envelopes
- client metadata models

## Likely future modules

### NexusProviders

Extract provider adapter interfaces and implementations when complexity warrants.

### NexusTerminal

Extract shared terminal model/runtime helpers once macOS+iOS renderers both exist.

## Boundary rules

- UI depends on Domain + IPC.
- Service depends on Domain + IPC.
- Domain depends on nothing UI-specific.
- Provider adapters remain service-owned.
- Persistence remains service-owned.
