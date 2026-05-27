# Milestone Six

## Goal

Prove that Remote Client V1 is trustworthy enough for internal dogfooding by making reconnect and recovery behavior boringly reliable, clarifying health and failure states, and tightening interaction coherence across the existing iPhone-first surface.

## Success criteria

- a user can reopen the iPhone app on the same network and return to the last active **Paired Mac** without repeating **Pairing**
- iPhone restores the active **Paired Mac** after relaunch but does not automatically reopen the last active **Session**
- when an attached **Session** disconnects briefly, iPhone preserves the last known screen as stale, explains that reconnect is in progress, retries automatically while the screen remains open, and returns to a live screen when recovery succeeds
- reconnect retry stops when the user leaves the **Session** screen or the **Pairing** is revoked
- when iPhone backgrounds while acting as **Controller**, it returns to **Viewer** semantics and does not automatically retake **Controller** on foreground
- when Mac interaction reclaims **Controller**, the iPhone remains attached as a **Viewer** and clearly blocks further input until the user explicitly takes **Controller** again
- iPhone remote actions use a consistent contract for in-flight state, success refresh behavior, and failure handling across launch, relaunch, stop, delete, create, and controller actions
- iPhone shows product-shaped recovery messages when Nexus can classify a remote failure, with raw transport errors only as a fallback
- unhealthy **Workspace Availability**, **Provider Health**, revoked **Pairing**, unavailable **Paired Mac**, disabled **Remote Access**, and viewer-without-**Controller** states each produce understandable guidance about what to do next
- recents remain shortcut entry points into the canonical **Workspace** -> **Provider** -> **Session** structure rather than becoming a separate navigation mode
- the dedicated **Remote Client** API and Mac-side service may gain incremental compatibility-preserving improvements, but no transport redesign is required
- lightweight diagnostics breadcrumbs exist on iPhone and on the Mac for dogfood investigation of remote failures
- all must-pass dogfood scenarios have automated coverage at the iPhone model and/or dedicated remote API boundary where practical

## Scope

### In

- end-to-end hardening of the existing iPhone **Remote Client** surface
- reconnect and stale-screen recovery behavior for attached **Sessions**
- return-to-work improvements centered on the active **Paired Mac** and lightweight recents shortcuts
- product-shaped remote error classification and recovery copy
- clearer unhealthy-state handling for **Paired Mac**, **Remote Access**, **Pairing**, **Workspace Availability**, **Provider Health**, and **Controller** state
- interaction coherence across existing remote actions
- lightweight remote diagnostics breadcrumbs on iPhone and persistent diagnostics on the Mac
- incremental compatibility-preserving improvements to the dedicated **Remote Client** API and Mac-side service behavior when they directly improve dogfood readiness
- automated coverage in `nexusTests/RemoteClientPairingModelTests.swift` and `nexusTests/RemotePairingNetworkTests.swift`

### Out

- major new **Remote Client** capability work beyond dogfood-blocking friction removal
- automatic reopening of the last active **Session** after full iPhone app relaunch
- automatic retaking of **Controller** on foreground or reconnect
- queueing terminal input while disconnected
- iPhone creation or editing of **Workspace Groups**, **Hosts**, **Workspaces**, or Mac **Remote Access** settings
- custom naming or rename flows for **Named Sessions** on iPhone
- an explicit iPhone **Detach** action
- automatic nearby-Mac discovery as a milestone requirement
- public-release polish across every edge of the iPhone app
- transport or authentication redesign for the dedicated **Remote Client** API
- cloud relay, internet-wide access, wake-on-LAN, or Mac bootstrap behavior
- broad iPad-specific UX work

## UX minimums

### Reconnect and recovery

- stale attached **Session** screens keep the last known terminal content visible
- stale state clearly communicates that the iPhone is reconnecting rather than pretending the **Session** ended
- reconnect recovery returns to the live **Session** in place without forcing the user to rebrowse
- revoked **Pairing** clearly ends the relationship with that **Paired Mac** and requires a new **Pairing**

### Controller and viewer behavior

- iPhone clearly shows whether it is the **Controller** or a **Viewer**
- input affordances are blocked when iPhone is only a **Viewer**
- foreground return after backgrounding keeps the iPhone attached as a **Viewer** until **Take Controller** is tapped again
- Mac reclaim of **Controller** is obvious and non-destructive to iPhone attachment

### Health and failure clarity

- remote failures use concise product-shaped recovery copy where Nexus knows the cause
- browse-time summaries and action-time failures use the same domain language already defined by Nexus
- unhealthy **Workspace** and **Provider** states remain inspectable even when actions are unavailable
- recents always route back into the canonical **Workspace**, **Provider**, or **Session** flow

## Core rules

- **Milestone Six** is a hardening milestone for existing **Remote Client** behavior, not a broad capability-expansion milestone
- completion is judged by must-pass dogfood scenarios rather than by raw bug-count reduction
- priority order is: reconnect confidence first, health and error trustworthiness second, terminology and interaction coherence third
- iPhone restores the active **Paired Mac** after app relaunch but not the last active **Session**
- stale reconnect behavior is acceptable as long as it is understandable and recovers in place when possible
- the iPhone remains attached as a **Viewer** after reconnect unless it explicitly takes **Controller** again
- iPhone backgrounding releases **Controller** and does not silently reclaim it later
- action-time failure may still contradict stale browse-time health; the milestone should make those contradictions understandable rather than eliminate every race
- recents are accelerators into the workspace-first model, not a second product structure
- a trusted **Paired Device** continues to be authorized against its **Paired Mac** as a whole in V1
- Mac-side and service-side changes are allowed only when they directly improve **Remote Client** dogfood readiness
- every must-pass dogfood scenario should be backed by automated tests where practical

## Must-pass dogfood scenarios

1. pair once, close the iPhone app, reopen later on the same network, and browse the same **Paired Mac** again
2. open a **Session**, lose connection briefly, and recover from stale terminal content back to a live **Session** without panic
3. take **Controller**, type, background the phone, return, and continue as a **Viewer** until explicitly taking **Controller** again
4. hit an unhealthy **Workspace**, **Provider**, revoked **Pairing**, unavailable **Paired Mac**, or disabled **Remote Access** state and understand what to do next

## Open implementation choices

- exact retry cadence or backoff policy for stale **Session** reconnect attempts
- exact taxonomy and copy for product-shaped remote error classification
- exact minimal diagnostics breadcrumb format on iPhone and on the Mac
- exact recents-surface refinements that improve return-to-work speed without weakening the workspace-first model
- exact compatibility-preserving dedicated **Remote Client** API adjustments needed to support better reconnect and diagnostics behavior
