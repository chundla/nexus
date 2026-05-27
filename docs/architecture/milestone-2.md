# Milestone Two

## Goal

Prove the Nexus remote-workspace architecture with a useful macOS-only remote slice centered on the Background Service.

## Historical note

Milestone Two captured the first remote SSH-plus-tmux provider slice with Claude. Current rollout status is:

- Claude and Codex are the remote **Launchable Providers** on supported **Remote Workspaces**
- iPhone reuses the same Workspace-scoped remote capability surface through the dedicated **Remote Client** API
- Pi and IBM Bob remain visible **Providers** but are not launchable yet

## Success criteria

- user can create, edit, validate, and inspect a Host
- Host setup is SSH-config-first, with optional light connection overrides such as port
- user can create a Remote Workspace from a Host plus absolute remote path
- Remote Workspaces appear in the same Workspace Groups, recents, and quick switch flows as local Workspaces
- remote Workspace overview shows Host, remote path, Workspace Availability, compact Host Validation context, and provider cards
- Nexus keeps Host Validation, Workspace Availability, and Provider Health as separate concepts
- remote checks follow the dependency order Host Validation -> Workspace Availability -> Provider Health
- blocked or uncheckable remote checks are surfaced distinctly from actual failure
- Nexus can evaluate remote Claude Provider Health for a specific Remote Workspace using a workspace-aware launch probe
- user can launch or resume the default remote Claude Session over SSH with tmux
- user can create additional named remote Claude Sessions
- failed remote launches become inspectable failed Session records
- Stop Session terminates the remote tmux-backed runtime; detach leaves runtime alive
- tmux-backed remote Claude Sessions are recoverable after Background Service restart using persisted linkage
- Providers outside the first implemented remote launch set still appear on Remote Workspaces as supported product concepts, but are clearly not launchable in this milestone

## Scope

### In

- macOS app target
- embedded Background Service target
- NexusDomain and NexusIPC expansion for local and remote Workspace Targets
- first-class Host entity with service-owned persistence
- Host creation, editing, validation, revalidation, and diagnostics
- inline Host creation during Remote Workspace creation
- Remote Workspace creation from Host + absolute remote path + primary group, with optional/defaulted name
- global uniqueness for Remote Workspaces by effective target (Host + absolute remote path)
- workspace-first navigation that keeps local and remote Workspaces in the same groups and quick switch flows
- Host detail view that owns Host Validation and Host diagnostics
- remote Workspace overview updates for Host and remote-path context
- remote Claude Provider Health using SSH plus workspace-aware checks
- SSH transport for remote execution
- tmux as the fixed Remote Session Strategy in this milestone
- default remote Claude Session plus additional named remote Claude Sessions
- failed remote Session records with diagnostics
- persisted snapshots for Host Validation, Workspace Availability, and remote Provider Health
- persisted remote runtime linkage needed for tmux-backed Session recovery
- remote Launch Snapshots that capture resolved remote execution details
- provider-native remote authentication, with light auth-readiness detection where feasible

### Out

- iOS target work
- pairing or remote-client protocol work
- additional remote launchable Providers beyond the first implemented remote slice
- user-selectable Remote Session Strategy
- automatic adoption or discovery of arbitrary tmux sessions
- remote Workspace auto-discovery
- broad remote provider configuration UI
- Host-first top-level navigation that competes with the workspace-first model
- Host grouping, tagging, favorites, or other richer Host organization
- SSH secret management, private key management, or password storage
- relative or `~`-based saved remote Workspace paths
- in-place mutation of a Remote Workspace target; changing Host or remote path creates a new Remote Workspace instead

## UX minimums

### Home/navigation

- local and remote Workspaces appear together in Workspace Groups
- local and remote Workspaces appear together in recents
- quick switch remains workspace-first
- Remote Workspaces are distinguished by explicit product metadata, not naming conventions alone
- Hosts are reachable through a secondary management surface and links from Remote Workspaces

### Host management

- create Host
- edit Host metadata and light connection overrides
- validate/revalidate Host
- inspect Host diagnostics and last-checked state
- block Host deletion while any Remote Workspace still references it

### Remote Workspace creation

- select an existing Host or create one inline
- enter an absolute remote path
- choose primary group using the existing workspace-group model
- allow creation even when Host Validation is currently failing, with clear warnings

### Remote Workspace overview

- workspace name
- primary group
- Host
- absolute remote path
- Workspace Availability
- compact Host Validation summary or clear link to Host detail
- last-checked or staleness cues where relevant
- provider cards for all supported Providers
- default Session status and action
- compact count of additional Sessions

### Provider detail

- same structural shape as milestone one
- default Session
- named Sessions
- failed Session records
- launch/new session actions
- remote Provider Health and diagnostics

### Session screen

- same terminal-first shape as milestone one
- remote context such as Host and remote path shown in session chrome/metadata
- detach remains distinct from Stop Session

## Core rules

- Host Validation is provider-agnostic
- Workspace Availability is distinct from Host Validation and Provider Health
- remote path accessibility belongs to Workspace Availability, not Host Validation
- Provider Health for a remote **Launchable Provider** is **Remote Workspace**-scoped, not Host-scoped
- launch/resume may opportunistically revalidate Host, Workspace Availability, and Provider Health before launching
- unavailable and broken are not synonyms:
  - unavailable means transient environmental failure
  - broken means saved target/configuration requires repair
- the same unavailable/broken distinction applies to Hosts
- invalid Hosts remain selectable during Remote Workspace creation
- Remote Workspace target identity is Host + absolute remote path
- Remote Workspace uniqueness is global across the app, not scoped to Workspace Group
- Remote Workspace target changes are modeled as new Remote Workspaces
- Remote Sessions are recovered only through persisted Nexus-owned linkage, not by adopting arbitrary tmux sessions
- if a tmux-backed remote runtime disappears outside Nexus, the Session record remains inspectable and explicitly relaunchable rather than being silently recreated
- a fresh relaunched remote runtime gets a new tmux session identifier even when the Nexus Session lane stays the same

## Open implementation choices

- exact staleness policy for automatic remote revalidation
- exact SSH command execution wrapper and failure classification strategy
- exact tmux naming/identifier strategy for Nexus-owned remote runtimes
- exact macOS placement of the Host management entry point
