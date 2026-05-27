# Milestone Seven

## Goal

Prove that Nexus is truly provider-general by making Codex a fully launchable Provider everywhere Claude already works, while moving Claude onto the same internal provider-adapter seam.

## Success criteria

- user can inspect local Codex Provider Health on a local Workspace
- user can launch or resume the default local Codex Session for a Workspace
- user can create additional local Codex Named Sessions
- Codex Session Records follow the same stop, relaunch, inspect, and delete rules as existing Claude Session Records
- remote Workspace overview shows remote Codex Provider Health using the same Workspace-scoped dependency chain as other remote checks
- user can launch or resume the default remote Codex Session over SSH with tmux
- user can create additional remote Codex Named Sessions
- remote Codex Sessions use the same detach, stop, and recovery semantics as remote Claude Sessions
- iPhone can inspect Codex health and use the same supported remote launch and Named Session flows when Codex is a Launchable Provider on the active Paired Mac
- shared macOS and iPhone surfaces no longer hardcode Claude-only gating or Claude-only shared copy
- the Background Service computes action-ready Provider Capability state consistently for macOS and iPhone
- Claude uses the same internal provider-adapter seam as Codex
- Pi and IBM Bob remain visible as Providers but are clearly non-launchable in this milestone
- automated coverage proves Codex parity across local IPC, dedicated remote network flows, and iPhone model behavior, while protecting Claude regression coverage on the new seam

## Scope

### In

- a small internal service-owned provider-adapter seam inside `NexusService`
- adapter-backed provider behavior for Claude and Codex
- local Codex Provider Health based on executable resolution, version detection when possible, a lightweight launchability probe, and structured diagnostics
- local Codex default Session launch/resume and Named Session creation
- remote Codex Provider Health using the existing Host Validation -> Workspace Availability -> Provider Health dependency model
- remote Codex execution using the existing SSH plus tmux Remote Session Strategy
- remote Codex recovery through the existing persisted Nexus-owned linkage model
- action-ready Provider Capability state for default-session launch/resume and Named Session creation
- Provider Capability exposure through shared domain models used by local IPC and the dedicated Remote Client API
- macOS and iPhone affordance gating driven by service-owned Provider Capability and Provider Health rather than provider-name conditionals
- provider-aware shared copy on touched session/runtime surfaces
- Codex-specific local and remote diagnostics and launch-failure messaging
- explicit product/docs copy that presents Codex as a launchable Provider
- a brief roadmap cue that the new seam is intended to lower the cost of making Pi and IBM Bob launchable later

### Out

- Pi implementation
- IBM Bob implementation
- new provider configuration UI
- default launch args, env override UI, or broader ProviderConfig rollout
- broad Launch Snapshot expansion beyond what Codex strictly requires
- Codex-specific navigation or a provider-specific top-level product structure
- changes to the existing remote SSH/tmux contract beyond reusing it for Codex
- auth management beyond provider-native terminal auth and light readiness diagnostics where feasible
- a broad Provider Capability matrix for every possible Session action
- persisted Provider Capability snapshots as a separate source of truth
- iPhone feature expansion beyond Codex parity on existing supported flows

## UX minimums

### Workspace overview

- Codex appears in the existing provider-card model
- a launchable Codex card shows actionable default-session affordance
- an unavailable or unsupported Codex action explains itself through existing health/capability language
- shared overview affordances do not special-case Claude in user-facing wording

### Provider detail

- Codex uses the same provider-detail structure as Claude
- default Session, Named Sessions, and Failed Session Records use the same product model
- launch and create affordances follow service-owned Provider Capability state
- disabled actions use capability reasons for product-support limits and health summaries for readiness limits

### Session screen

- a Codex Session uses provider-aware shared copy rather than Claude-branded shared copy
- local and remote session metadata stay in the same places as existing sessions
- remote Detach remains distinct from Stop Session

### iPhone Remote Client

- Codex appears through the same workspace-first browsing structure
- Codex default-session launch/resume is available when the active Paired Mac exposes that capability as enabled
- Codex Named Session creation is available when the active Paired Mac exposes that capability as enabled
- iPhone uses the same disabled-state and recovery-language rules as macOS for Codex actions

## Core rules

- Milestone Seven is a provider-breadth milestone, not a new remote-client architecture milestone
- Codex is the only new fully Launchable Provider in this milestone
- Codex uses the current minimal provider launch contract:
  - executable name: `codex`
  - version probe: `codex --version`
  - launchability probe: `codex --help`
  - session launch: run `codex` in the Workspace working directory with no default extra args
- provider-native authentication remains terminal-native and is not a prerequisite for launchability
- Codex adopts the existing Default Session, Named Session, and Session Record model unchanged
- Codex reuses the existing remote SSH/tmux durability, detach, stop, and recovery contract unchanged
- Provider Capability is service-owned, computed on read, and exposed consistently through local IPC and the dedicated Remote Client API
- Provider Capability stays narrow in this milestone and covers only default-session launch/resume and Named Session creation
- Provider Capability answers whether Nexus supports an action on a target; Provider Health answers whether it can succeed now
- shared UI must not infer supported actions from provider names alone
- Launch Snapshot remains minimal unless Codex proves it insufficient
- Claude and Codex both use the same internal provider-adapter seam by milestone completion
- Pi and IBM Bob remain visible as Providers but non-launchable in this milestone
- the new provider-adapter seam is intended to reduce the future cost of making Pi and IBM Bob launchable, but that follow-on work is not part of this milestone

## Open implementation choices

- exact internal provider-adapter protocol and type layout inside `NexusService`
- exact shared-model shape for action-ready Provider Capability state
- exact Codex local and remote diagnostic copy
- exact migration strategy for replacing touched Claude-only gating and wording across macOS and iPhone surfaces
