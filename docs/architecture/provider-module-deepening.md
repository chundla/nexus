# Provider Module deepening plan

This document turns ADR 0034 into an implementation sequence. The target shape is one service-owned **Provider Module** seam per **Provider**. That **Module** owns **Provider Health**, catalog results and text, **Session** transition planning, and runtime construction using shared runtime **Adapter** implementations.

## Target seam

Shared modules keep:
- **Host Validation** and **Workspace Availability**
- **Session Record** and Launch Snapshot persistence writes
- live runtime registration, observation, and teardown
- shared runtime **Adapter** implementations such as `ProcessSessionRuntime`, `PiRPCSessionRuntime`, `CodexAppServerRuntime`, and `IBMBobSessionRuntime`

Each **Provider Module** owns:
- one catalog read result reused by **Workspace Overview** and **Provider Detail**
- **Provider Health** derivation, snapshot reuse policy, capabilities, prelaunch **Session Surface**, and module-owned user-facing text
- one **Session** transition plan covering fresh open, persisted relaunch, and first-input bootstrap for **Sessions** that may remain **ready** without runtime
- runtime construction by choosing and assembling shared runtime **Adapter** implementations

Shared code should stop knowing Provider-specific launch, relaunch, readiness, and summary rules.

## Planned slices

1. Freeze the new **Provider Module** interface beside the current seam.
   - add the new catalog result, **Session** transition plan, and runtime-construction entry points
   - keep persistence writes outside the seam so tests can exercise plans without stores hidden behind the interface

2. Move runtime construction behind the seam.
   - remove Provider selection from `ServiceSessionProviderRegistry`
   - let each **Provider Module** choose terminal-backed, structured, local, and remote runtime **Adapter** construction

3. Move **Session** transition policy behind the seam.
   - fresh open
   - persisted relaunch
   - first-input bootstrap for **ready**-without-runtime **Sessions**
   - continuity metadata source and retry-without-continuity policy
   - Provider-specific recovery-failure classification and user-facing guidance

4. Move catalog and **Provider Health** behind the seam.
   - module-owned health derivation and snapshot reuse policy
   - module-owned capability rules and prelaunch **Session Surface**
   - module-owned summary, disabled-reason, and relaunch text
   - make `WorkspaceCatalog` an assembly module rather than a policy module

5. Delete shallow leftovers.
   - delete `ServiceProviderAdapter`
   - delete generic runtime-factory maps
   - delete remaining Provider-specific branches in `NexusService`
   - delete any lasting generic fallback **Module** once all supported **Providers** have dedicated modules

## Migration order

Migrate **Providers** in this order:
1. Claude — terminal-backed control case
2. Pi — richest remote relaunch and continuity case
3. Codex — structured runtime with simpler policy
4. IBM Bob — ready-without-runtime and first-input bootstrap case

This keeps one real seam while proving it across all current **Session** shapes.

## Test surface

The **Provider Module** interface is the main test surface.

Add or keep:
- per-Provider scenario tests for catalog read, **Provider Health**, fresh open, persisted relaunch, first-input bootstrap, and runtime construction
- thin shared tests proving `WorkspaceCatalog`, lifecycle, and interaction code apply returned plans correctly

Reduce tests whose only job is proving shared code ignored `ServiceProviderAdapter` overrides, because those tests describe the shallow shape we are deleting.

## Touched files

The deepest slices will likely touch:
- `Modules/Sources/NexusService/ProviderModule.swift`
- `Modules/Sources/NexusService/ServiceSessionProviderRegistry.swift`
- `Modules/Sources/NexusService/WorkspaceCatalog.swift`
- `Modules/Sources/NexusService/ServiceSessionLifecycle.swift`
- `Modules/Sources/NexusService/ServiceSessionInteraction.swift`
- `Modules/Sources/NexusService/NexusService.swift`
- dedicated Provider modules for Claude, Pi, Codex, and IBM Bob
- `Modules/Tests/NexusServiceTests/*ProviderModule*`

## Non-goals

This refactor does not change product meaning for **Workspace**, **Provider**, **Session**, **Session Surface**, or **Remote Session Strategy**. It changes where the rules live so Provider behavior gains more **locality** and callers gain more **leverage** from one seam.