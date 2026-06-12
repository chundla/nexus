# Nexus

Nexus is a workspace-first control center for coding agent CLIs across local and remote environments. The product centers **Workspaces**, **Providers**, and **Sessions**, with a macOS app talking to a service-owned **Background Service** over real local IPC.

## Current repo status

- This checkout builds a multiplatform `nexus` app target (macOS control center + iOS **Remote Client**) and shared service/domain modules.
- Nexus supports both terminal-backed and protocol-native **Sessions** behind one shared **Session** model.
- Local Pi is the first documented protocol-native **Provider** path.
- `docs/architecture/milestone-14.md` is the latest rollout-planning document (remote IBM Bob structured **Provider** on **Remote Workspaces**).
- Older milestone docs and the PRD are historical snapshots; use them for rollout history, not as the sole source of current truth.

## Start here

1. `CONTEXT.md` — canonical product language
2. `ARCHITECTURE.md` — stable high-level architecture and doc map
3. `docs/architecture/milestone-14.md` — latest planned rollout direction
4. `docs/adr/README.md` — index of durable architecture decisions
5. `docs/prd/nexus-workspace-first-control-center.md` — historical milestone-one product framing
6. `docs/performance-baselines.md` — repeatable launch and service flow baseline workflow

## Build

```bash
xcodebuild -scheme nexus -project nexus.xcodeproj build
```

## Test

```bash
xcodebuild test -scheme nexus -project nexus.xcodeproj -destination 'platform=macOS'
swift test --package-path Modules
```

## Repo layout

- `nexus/` — macOS app target
- `Modules/Sources/NexusDomain` — shared domain types and vocabulary
- `Modules/Sources/NexusIPC` — local IPC contracts and client
- `Modules/Sources/NexusService` — service-owned orchestration, persistence, provider modules, session runtime logic
- `Modules/Sources/NexusSessionPresentation` — shared structured **Session Presentation** projection
- `docs/architecture/` — architecture reference and milestone rollout docs
- `docs/adr/` — architecture decision records
- `docs/prd/` — product framing docs

## Reading notes

- `CONTEXT.md` is the best source for product terminology.
- `ARCHITECTURE.md` describes the stable product shape; milestone docs describe rollout slices.
- If two docs disagree about rollout status, prefer the newer milestone doc and the ADRs over older future-tense planning text.
