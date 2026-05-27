# Milestone Three

## Goal

Prove the first iPhone-first Remote Client slice for Nexus by pairing an iPhone to a Mac over the local network and remotely browsing, attaching to, and controlling Mac-managed Sessions.

## Current rollout note

By Milestone Seven, iPhone can browse, inspect **Provider Health**, and use the supported remote launch and **Named Session** flows for both Claude and Codex when the active **Paired Mac** reports them as **Launchable Providers**. Pi and IBM Bob remain visible **Providers** but are not launchable yet.

## Success criteria

- user can explicitly enable **Remote Access** on a Mac while Nexus is running
- user can complete first-time **Pairing** from the Mac with durable trust for a **Paired Device**
- user can reconnect from iPhone to the last-used **Paired Mac** by default, with a secondary switcher for other **Paired Macs**
- iPhone discovers reachable **Paired Macs** automatically on the local network, with manual recovery when discovery fails
- iPhone can browse the active **Paired Mac** using the same workspace-first model, including **Workspace Groups**, recents, and active/default Session context
- iPhone can inspect **Workspace Availability**, **Provider Health**, and existing Session state before launch
- iPhone can attach to local and remote Mac-managed Sessions as a viewer by default
- iPhone can render a true terminal viewport for an attached Session
- iPhone can take **Controller** status without Mac-side approval and can send real terminal input through a minimal iPhone input UI
- any human interaction in Nexus on the Mac automatically reclaims **Controller** status
- the current **Controller** owns terminal size; taking control from iPhone resizes the Session to the iPhone viewport and Mac reclaim resizes it back
- iPhone can launch, resume, relaunch, and stop the default Session for a **Launchable Provider** on the active **Paired Mac**
- iPhone can view and operate existing named Sessions that already exist on the active **Paired Mac**, but cannot create additional named Sessions yet
- iPhone can inspect failed Session records and relaunch them when appropriate
- provider-native auth prompts remain terminal-native and can be completed from iPhone through the Session terminal
- if iPhone disconnects, the Session keeps running on the Mac and iPhone reconnects as a viewer by default
- closing the Mac Nexus window does not break iPhone control; quitting Nexus on the Mac may disconnect the iPhone in this milestone
- a locked Mac may still serve paired iPhone connections while Nexus is running and the Mac is awake and reachable
- Mac can list and revoke **Paired Devices**; iPhone can forget a **Paired Mac**

## Scope

### In

- iPhone-first iOS app target work
- dedicated network Remote Client API that reuses Nexus domain concepts instead of exposing local XPC directly
- authenticated and encrypted per-device trust established by **Pairing** for later reconnects
- Mac-side **Remote Access** opt-in management while Nexus is running
- first-time Mac-initiated **Pairing** flow with durable trust
- automatic local-network discovery for reachable **Paired Macs**
- manual recovery path when discovery fails
- support for many **Paired Macs** over time, with one active Mac connection at a time on iPhone
- last-used **Paired Mac** auto-reconnect behavior with a secondary Mac switcher
- workspace-first iPhone browsing for the active **Paired Mac**, preserving **Workspace Groups**
- summary-first remote catalog loading with details on demand
- lightweight stale read-only cache on iPhone for recent Workspace and Session state
- lightweight iPhone inspection and refresh of **Workspace Availability** and **Provider Health**
- iPhone attach/view support for all Mac-managed Sessions whose underlying Provider support is actually implemented
- viewer-by-default attachment model on iPhone
- true terminal viewport rendering on iPhone
- real terminal input path on iPhone with a minimal control surface suitable for phone use
- explicit take-control action from any viewer without bilateral handoff approval
- automatic Mac reclaim of **Controller** status on Mac Nexus interaction
- automatic iPhone loss of **Controller** status when the iPhone app backgrounds
- controller-owned Session resize behavior
- default Session launch/resume/relaunch/stop from iPhone
- attach/view/control existing named Sessions without named-Session creation on iPhone
- failed Session inspection and relaunch from iPhone
- Stop Session confirmation on iPhone
- provider-native auth through the terminal from iPhone
- minimal pairing management on both Mac and iPhone

### Out

- iPad-first or broad iPad-specific UX work
- workspace creation, workspace editing, or Host management from iPhone
- additional named Session creation from iPhone
- delete-record actions for Session records from iPhone
- file browsing, editor navigation, or mobile IDE workflows
- iPhone notifications or push alerting for Session events
- wake-on-LAN, sleep recovery, or internet-wide remote access
- cloud relay, account system, or non-local-network pairing
- per-device capability matrices or partial workspace visibility rules
- extra Nexus-specific auth prompts on iPhone after durable Pairing
- remote Background Service admin actions such as restart or full diagnostics-log management from iPhone
- a requirement that Nexus remote access survive full Mac app quit or reboot without relaunch
- a merged cross-Mac workspace catalog on iPhone
- pretending non-implemented Providers are launchable from iPhone

## UX minimums

### Mac Remote Access management

- explicit enable/disable control for **Remote Access**
- first-time Pairing entry point from the Mac
- pairing code and/or QR ceremony for the iPhone
- list of trusted **Paired Devices**
- revoke **Paired Device** action
- secondary management placement rather than top-level workspace navigation

### iPhone connection flow

- reconnect to last-used **Paired Mac** by default
- secondary switcher for other **Paired Macs**
- visible unavailable state when the chosen **Paired Mac** is offline, asleep, or Nexus is not running
- auto-discovery of reachable **Paired Macs** with a manual fallback/recovery path
- forget-**Paired Mac** action on iPhone

### iPhone home/navigation

- workspace-first navigation for one active **Paired Mac** at a time
- **Workspace Groups** preserved
- recents and active Sessions more prominent than on Mac
- clear active-Mac context in the chrome
- all Workspace and Session browsing reflects the active **Paired Mac** only

### Workspace and Provider detail on iPhone

- Workspace summary
- **Workspace Availability** summary and refresh action
- Provider list for supported product concepts
- **Provider Health** summary and refresh action
- clear indication when a Provider exists conceptually but is not launchable on the active **Paired Mac**
- default Session summary and action
- existing named Session summaries
- failed Session summaries

### Session screen on iPhone

- true terminal viewport
- clear viewer vs **Controller** status
- explicit take-control action
- obvious loss/reclaim of **Controller** status
- minimal but real terminal input UI
- Stop Session action with confirmation
- Session metadata that keeps Workspace and Provider ownership visible
- remote disconnect state that preserves last known content as stale read-only until reconnect

### Multi-client behavior

- many viewers, one **Controller**
- any viewer may take **Controller** status
- local Mac Nexus interaction automatically reclaims **Controller** status
- the current **Controller** owns terminal size

## Core rules

- iPhone is a **Remote Client**, not an execution host
- the Mac Background Service remains the execution authority and source of truth
- **Remote Access** is explicit opt-in on the Mac and only works while Nexus is running
- first-time **Pairing** is Mac-initiated and requires physical access to the Mac
- successful **Pairing** grants access to all Workspaces and Sessions on that Mac
- reconnects after **Pairing** use durable per-device authenticated and encrypted trust
- iPhone does not require an extra Nexus-specific auth prompt after durable Pairing in this milestone
- a locked Mac may still serve a paired iPhone if the Mac is awake, reachable, and Nexus is running
- iPhone browsing is scoped to one active **Paired Mac** at a time
- iPhone preserves the workspace-first product model rather than switching to a session-first product model
- iPhone may browse all Workspaces and Sessions on the active **Paired Mac**
- iPhone may operate only Providers whose Mac-side support is actually implemented
- iPhone attaches to Sessions as a viewer by default
- any viewer may take **Controller** status without approval from the current controller
- Mac Nexus interaction automatically reclaims **Controller** status
- iPhone backgrounding drops **Controller** status
- the current **Controller** owns terminal size
- network loss disconnects the **Remote Client** attachment, not the Session runtime
- reconnect after disconnect reopens the Session as a viewer by default
- iPhone may launch/resume/relaunch/stop Sessions but may not create additional named Sessions or delete Session records in this milestone
- provider-native auth remains terminal-native even when completed from iPhone
- bounded scrollback is always available on iPhone; broader history follows the Session transcript policy
- closing the Mac Nexus window is distinct from quitting the Mac Nexus app
- full Mac app quit or reboot may interrupt Remote Client access until Nexus is relaunched

## Open implementation choices

- exact local-network discovery mechanism for **Paired Macs**
- exact pairing payload format and how QR vs manual code entry coexist
- exact transport/protocol framing for the dedicated network Remote Client API
- exact placement and wording of the Mac **Remote Access** management surface
- exact minimal iPhone terminal input affordances beyond text entry, return, backspace, and control keys such as Ctrl-C
- exact staleness and eviction policy for the iPhone’s local cache
- exact behavioral threshold for what Mac-side Nexus interactions count as automatic **Controller** reclaim
