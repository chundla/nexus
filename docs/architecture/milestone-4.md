# Milestone Four

## Goal

Prove that a trusted iPhone **Remote Client** can create and enter additional **Named Sessions** on an active **Paired Mac** while preserving the existing workspace-first, viewer-by-default model.

## Success criteria

- iPhone can create an additional **Named Session** from **Provider detail** on the active **Paired Mac**
- the create action works for local and **Remote Workspaces** whose **Provider** is actually operable on that **Workspace**
- the **Named Sessions** section is visible on iPhone even when no **Named Sessions** exist yet
- the create action is visible for supported product Providers but disabled when **Provider Health** says the Provider is not operable or launchable on that **Workspace**
- creating a **Named Session** uses an auto-generated name and immediately attempts launch rather than creating a record-only lane
- after create, iPhone opens the created **Session** immediately, including when the created **Session** is a failed Session record
- after create, iPhone attaches to the created **Session** as a viewer by default rather than automatically taking **Controller** status
- the creating iPhone refreshes **Provider detail** and catalog state immediately so the new **Named Session** appears when the user backs out
- the flow uses the existing **Pairing** trust model with no extra Mac-side approval and no new Mac user-facing surface
- remote create failures use the same generic iPhone remote error handling as other remote actions
- automated coverage proves the flow through dedicated remote-network tests and iPhone model tests

## Scope

### In

- iPhone-first **Remote Client** depth work
- dedicated **Remote Client** API expansion for remote **Named Session** creation using domain concepts
- authorized remote **Named Session** creation for any trusted **Paired Device** on the active **Paired Mac**
- create action in iPhone **Provider detail** within the **Named Sessions** area
- empty-state **Named Sessions** section on iPhone with a create action
- action-local refresh of iPhone **Provider detail** and catalog after create
- immediate navigation into the created **Session** after create
- reuse of existing failed Session inspection and relaunch behavior when create returns a failed Session record
- terminology cleanup on touched surfaces to **Named Sessions**
- automated coverage in `nexusTests/RemotePairingNetworkTests.swift` and `nexusTests/RemoteClientPairingModelTests.swift`

### Out

- workspace creation, workspace editing, or **Host** management from iPhone
- Session-record deletion from iPhone
- **Named Session** rename from iPhone
- global or session-first create flows outside **Workspace** -> **Provider** -> **Named Sessions**
- create shortcuts on iPhone workspace overview/provider-card summary surfaces
- automatic **Controller** takeover after create
- live cross-client list streaming for provider/session lists
- provider-breadth expansion solely to support this milestone
- extra Mac approval prompts, capability matrices, or new Mac management UI for remote create
- broad iPad-specific UX work
- broad new iPhone UI-test investment as a milestone requirement

## UX minimums

### iPhone Provider detail

- **Named Sessions** section remains visible even when empty
- empty state clearly says there are no **Named Sessions** yet
- a **Create Session** action lives with the **Named Sessions** section
- **Create Session** is visible but disabled when the **Provider** is not operable on that **Workspace**
- disabled create state explains why the **Provider** cannot currently create a **Session**
- existing **Named Sessions** and failed Session records remain visible in the same detail surface

### iPhone Session screen after create

- the created **Session** opens immediately after create
- a successfully launched created **Session** opens as a viewer by default
- a failed created **Session** opens with failure context and relaunch capability
- Workspace and Provider ownership remain visible in Session metadata

## Core rules

- a trusted **Paired Device** may create a **Named Session** on its **Paired Mac** without extra Mac-side approval
- iPhone **Named Session** creation is create-and-attempt-launch, not record-only creation
- iPhone blocks the create action when **Provider Health** already says the **Provider** is not launchable or is blocked for that **Workspace**
- stale health may still race with the environment, so a create attempt may still produce a failed Session record
- a **Default Session** does not need to exist before creating a **Named Session**
- iPhone stays workspace-first; **Named Session** creation remains scoped under one **Workspace** and one **Provider**
- iPhone enters the created **Session** as a viewer by default and may explicitly take **Controller** status afterward
- action-local refresh is sufficient for this milestone; other clients may see the new **Named Session** on their next refresh
- only Providers whose Mac-side support is actually implemented may be operable create targets in this milestone

## Open implementation choices

- exact dedicated **Remote Client** route shape for **Named Session** creation while keeping the API domain-first
- exact small iPhone progress and disabled-state copy for the create action
