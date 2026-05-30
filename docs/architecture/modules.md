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
- ADR 0034 sets the target shape: one **Provider Module** seam per **Provider**, with no lasting `ServiceProviderAdapter` fallback.
- the implementation plan lives in `docs/architecture/provider-module-deepening.md`.
- Claude, Codex, IBM Bob, and Pi now route catalog reads, **Provider Health**, **Session** transition planning, runtime construction, prelaunch **Session Surface** selection, and module-owned launch/relaunch policy through dedicated provider modules.
- shared code no longer relies on `ServiceProviderAdapter` or `providerAdapter(...)` fallbacks for Provider-specific behavior.
- `docs/architecture/provider-module-deepening.md` remains the durable implementation sequence for how the seam was deepened.

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

### NexusSessionPresentation

Responsibilities:
- shared structured **Session Presentation** projection from `SessionScreen` into render-ready state
- shared activity-row projection, conversation-role classification, pending **Approval Request** filtering, composer/send state, and slash-command menu state
- provider-aware copy for structured **Session Surfaces**

Must not own:
- primary **Session Surface** selection before a caller enters structured presentation
- platform-specific SwiftUI layout, theme, focus, scrolling, or animation
- terminal-backed **Session Surface** rendering

Current adapters:
- `nexus/ContentView.swift` is the macOS structured **Session Surface** adapter
- `nexus/RemoteClientHomeView.swift` is the iPhone structured **Session Surface** adapter

Implementation notes:
- the detailed seam record lives in `docs/architecture/session-presentation-deepening.md`
- terminal projection stays out of scope here and remains future `NexusTerminal` work

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
