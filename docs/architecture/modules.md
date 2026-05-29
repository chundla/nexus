# Module and Target Boundaries

## Immediate target split

### NexusApp

Responsibilities:
- macOS UI
- workspace-first navigation
- provider cards and provider detail screens
- provider-appropriate Session screens, including structured Session UI and terminal rendering when needed
- quick switch UI
- minimal diagnostics and service status UI
- local IPC client

Must not own:
- authoritative session lifecycle
- provider adapter logic
- persistence
- protocol-native runtime orchestration
- PTY/process orchestration

### NexusService

Responsibilities:
- Background Service runtime
- authoritative state and persistence
- provider adapters
- provider modules
- health checks
- launch snapshot resolution
- session lifecycle orchestration
- shared Session streams and presentation state
- protocol-native runtime ownership
- PTY/process ownership where a Provider exposes a terminal surface
- diagnostics

Current bootstrap implementation:
- lives in the shared `NexusService` module
- is bootstrapped by the app through `NexusEmbeddedServiceBootstrap`
- exposes a narrow embedded-session surface to the app (`listenerEndpoint`, `storeURL`)
- currently proves the boundary with service-owned SQLite metadata-store creation
- the service now owns persisted Workspace Groups and local Workspaces in that store
- the app reads and mutates that catalog over real local IPC

### Current Provider Module seam

- `ProviderModule` is the service-owned seam between shared **Workspace Catalog** / **Session** lifecycle orchestration and provider-owned behavior.
- generic providers may still use `ServiceProviderAdapter` directly as the module implementation while the seam is being deepened.
- Pi currently routes catalog reads, fresh-open planning, persisted relaunch planning, structured prelaunch surface selection, and remote recovery/invalid-continuity policy through `PiProviderModule`.
- the split plus fresh-open/relaunch seam-shrinking slices are in place; remaining no-behavior-change follow-up is to move Pi health/support/snapshot-reuse policy into the Pi module, then remove remaining shared `providerAdapter(...)` leakage.
- issue #115 is the roadmap umbrella for that sequence; child slices #116 through #120 carry the implementation work in order.

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

### NexusSessionPresentation

Extract shared Session-stream and presentation helpers once structured Session UI exists for more than one Provider.

## Boundary rules

- UI depends on Domain + IPC.
- Service depends on Domain + IPC.
- Domain depends on nothing UI-specific.
- Provider adapters remain service-owned.
- Persistence remains service-owned.
