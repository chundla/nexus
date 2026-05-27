# Milestone Five

## Goal

> **Historical note**
> This document captures the intended scope and decisions for Milestone Five at the time it was written. For current terminology and rollout status, prefer `CONTEXT.md`, `ARCHITECTURE.md`, and the newest `docs/architecture/milestone-*.md` document.

Prove that a trusted iPhone **Remote Client** can delete non-running **Session Records** on an active **Paired Mac** from iPhone **Provider detail** while preserving the existing workspace-first model and current **Pairing** trust boundary.

## Success criteria

- iPhone can delete a non-running **Session Record** from **Provider detail** on the active **Paired Mac**
- delete works for stopped, interrupted, and failed **Session Records**
- delete works for **Default Session Records**, **Named Sessions**, and **Failed Session Records** when they are not running
- deleting a **Default Session Record** removes the persisted record but does not remove the conceptual **Default Session** lane for that **Workspace** and **Provider**
- after deleting a **Default Session Record**, iPhone **Provider detail** shows the existing no-default state and **Launch** action
- iPhone exposes delete for any visible non-running **Session Record**, regardless of current **Provider Health** or whether that **Provider** supports iPhone launch/create flows
- iPhone does not expose delete for a live running **Session**
- iPhone uses a confirmation step before deleting a **Session Record**
- after successful delete, iPhone stays on the same **Provider detail** screen and refreshes **Provider detail** and catalog state immediately
- successful delete uses silent success with visible list refresh rather than a success alert or banner
- stale state races use the existing generic iPhone remote error handling when delete is rejected by the Mac
- unauthorized delete errors use the existing generic iPhone remote error handling and do not broaden automatic revoked-**Paired Mac** recovery behavior in this milestone
- the dedicated **Remote Client** API adds a session-scoped delete-record action for existing **Session Records**
- automated coverage proves the flow through dedicated remote-network tests and iPhone model tests

## Scope

### In

- iPhone-first **Remote Client** depth work
- dedicated session-scoped **Remote Client** API expansion for remote **Session Record** deletion
- authorized remote deletion of non-running **Session Records** for any trusted **Paired Device** on the active **Paired Mac**
- iPhone **Provider detail** swipe-to-delete affordances for deletable rows
- iPhone delete confirmation flow for **Session Records**
- action-local refresh of iPhone **Provider detail** and catalog after delete
- iPhone terminology cleanup on touched surfaces from **Failed Sessions** to **Failed Session Records**
- automated coverage in `nexusTests/RemotePairingNetworkTests.swift` and `nexusTests/RemoteClientPairingModelTests.swift`

### Out

- delete actions from the iPhone **Session** screen
- deletion of live running **Sessions**
- bulk delete or edit-mode multi-select cleanup flows on iPhone
- **Named Session** rename from iPhone
- workspace creation, workspace editing, or **Host** management from iPhone
- session creation flow changes beyond what milestone four already delivered
- extra Mac approval prompts, capability matrices, or new Mac management UI for remote delete
- broad new iPhone UI-test investment as a milestone requirement
- broad revocation-recovery changes for all remote mutation actions

## UX minimums

### iPhone Provider detail

- deletable rows use a swipe action rather than an always-visible destructive button
- non-running **Default Session Records** show a delete swipe action
- non-running **Named Sessions** show a delete swipe action
- **Failed Session Records** show a delete swipe action
- live running rows do not show a delete affordance
- deleting requires confirmation before the request is sent
- the confirmation copy makes clear that delete removes the Nexus **Session Record** and does not stop a live runtime
- after delete, the row disappears through normal refreshed state without extra success chrome
- the failed-record section label reads **Failed Session Records**

## Core rules

- remote delete is **Session Record** deletion, not runtime termination
- remote delete is allowed only when the **Session** is not running
- **interrupted** is deletable because it is a non-running **Session Record** state
- any trusted **Paired Device** may delete a non-running **Session Record** on its **Paired Mac** without extra Mac-side approval
- deleting a **Default Session Record** does not remove the conceptual **Default Session** lane for that **Workspace** and **Provider**
- iPhone remains workspace-first; delete is scoped under one **Workspace** and one **Provider** detail surface even though the remote API is session-scoped
- the dedicated remote delete action is session-scoped and uses `POST /remote-client/sessions/{sessionID}/delete-record`
- the dedicated remote delete action returns a simple success boolean on success
- stale state may race with the environment, so the iPhone may offer delete for a row that the Mac rejects at execution time; this uses the normal remote error alert flow
- unauthorized delete failures use the normal remote error alert flow in this milestone rather than expanding automatic revoked-**Paired Mac** cleanup semantics

## Open implementation choices

- exact small iPhone confirmation copy and swipe-action visual polish
