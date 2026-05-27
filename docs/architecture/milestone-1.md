# Milestone One

## Goal

Prove the Nexus architecture with a useful macOS-only local-workspace slice centered on the Background Service.

## Historical note

Milestone One captured the first local provider slice. Current rollout status is:

- Claude and Codex are the local **Launchable Providers** on supported **Workspaces**
- Pi and IBM Bob remain visible **Providers** but are not launchable yet
- the service-owned provider-adapter seam from Milestone Seven is intended to lower the future cost of making Pi and IBM Bob launchable later

## Success criteria

- user can add multiple local workspaces
- user can organize workspaces into primary groups
- user can open a workspace overview
- user sees all supported providers on each workspace
- Nexus can detect provider health for the implemented adapter
- user can launch or resume the default session for a workspace+provider
- user can create an additional named session
- user can switch quickly between workspaces/providers/sessions
- session terminal is interactive through the Background Service
- failed launches become inspectable failed session records

## Scope

### In

- macOS app target
- embedded Background Service target
- NexusDomain and NexusIPC shared modules
- SQLite-backed custom metadata store in the service
- local workspace creation via folder picker
- provider-first workspace overview
- one focused terminal view with fast switching
- basic global quick switch
- minimal service status UI
- minimal diagnostics/log viewer

### Out

- iOS target
- SSH/tmux remote execution
- remote host management UI
- provider installation/update management
- full transcript policy UI
- auto-discovery of local repositories
- multi-tab terminal UI
- multi-client terminal implementation

## UX minimums

### Home/navigation

- workspace groups
- workspace list
- recent items
- global quick switch

### Workspace overview

- workspace name
- primary group
- local path
- availability state
- provider cards for all supported providers
- default session status and action
- compact count of additional sessions

### Provider detail

- default session
- named sessions
- failed session records
- launch/new session actions
- provider health/diagnostics

### Session screen

- terminal-first view
- restored last active session and basic viewing state when feasible

## Current bootstrap decisions

- local IPC bootstrap uses anonymous `NSXPCListener` / `NSXPCConnection`
- the first live service API is `getServiceStatus()`
- the Background Service owns a SQLite metadata store created by the service runtime

## Open implementation choices

- exact SQLite layer/library beyond the bootstrap store file
- exact macOS terminal component
- which provider adapter to implement first
