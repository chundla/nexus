# Nexus

Nexus is a workspace-first control center for coding agent CLIs across local and remote environments. This context captures the product language that should stay stable as the implementation grows.

## Language

**Workspace**:
A named working target that Nexus manages for launching and resuming provider sessions.
_Avoid_: project, repo

**Provider**:
A supported coding CLI integration that can be used inside a Workspace.
_Avoid_: tool, backend

**Provider Module**:
The Background Service module that owns one Provider's Provider Health, Provider Capability rules, primary Session Surface, launch/relaunch behavior, and Session Record continuation behavior.
_Avoid_: provider service, registry entry, launch helper

**Session**:
An app-owned provider-managed workstream for one Provider in one Workspace.
_Avoid_: process, tab, terminal

**Session Record**:
The persisted Nexus record for a Session, which may exist even when no live runtime is attached.
_Avoid_: process, terminal instance

**Default Session**:
The implicit reusable Session lane for one Provider in one Workspace.
_Avoid_: primary tab, main process

**Named Session**:
An additional explicitly created Session lane for one Provider in one Workspace.
_Avoid_: tab, branch session

**Host**:
A saved remote machine profile that remote Workspaces can use for execution defaults and validation.
_Avoid_: server config, SSH target

**Remote Workspace**:
A Workspace whose execution target is a Host and remote path rather than a local folder.
_Avoid_: synced workspace, mounted workspace

**Workspace Target**:
The concrete location a Workspace points at, either a local folder or a Host plus absolute remote path.
_Avoid_: generic path, folder field

**Remote Session Strategy**:
The mechanism used to keep a remote Session durable across attachment and detachment.
_Avoid_: workspace type

**Remote Client**:
A Nexus client, such as the iOS app, that attaches to Mac-managed Sessions over the network without becoming the execution host.
_Avoid_: remote workspace, execution host

**Controller**:
The one attached client currently allowed to perform Session-writing actions such as sending terminal input, structured prompts, or **Approval Request** decisions.
_Avoid_: owner, active viewer

**Viewer**:
An attached client that can observe a Session without performing Session-writing actions.
_Avoid_: passive controller, read-only owner

**Pairing**:
The trust-establishment flow that allows a **Remote Client** to reconnect to Nexus over the local network without repeating setup each time.
_Avoid_: login, sign-in

**Paired Mac**:
A Mac running Nexus that a **Remote Client** has already trusted and may reconnect to later.
_Avoid_: account, host

**Paired Device**:
A trusted **Remote Client** that a **Paired Mac** recognizes and may allow to reconnect later.
_Avoid_: account, user

**Remote Access**:
The Mac capability that allows **Remote Clients** to discover, pair with, and connect to Nexus over the local network while Nexus is running.
_Avoid_: host mode, cloud sync

**Host Validation**:
The status of whether Nexus can reach and authenticate to a Host and verify required remote execution capabilities.
_Avoid_: provider health, remote health

**Provider Health**:
The status of whether a Provider is available and launchable for a specific Workspace target; diagnostics may come from executable resolution, auth readiness, protocol handshake readiness, or other provider-specific launch prerequisites.
_Avoid_: host status, remote health

**Launchable Provider**:
A Provider whose current **Provider Health** says Nexus can start a Session for a specific Workspace target now.
_Avoid_: operable provider, enabled provider

**Provider Capability**:
A product-supported action Nexus exposes for a Provider on a specific Workspace target, such as launching the **Default Session** or creating a **Named Session**.
_Avoid_: hidden feature flag, UI-only affordance

**Workspace Overview**:
The provider-first summary Nexus shows for one Workspace, including current Provider summaries and Session entry points.
_Avoid_: workspace dashboard, project summary

**Provider Detail**:
The provider-focused summary Nexus shows for one Provider in one Workspace, including Session lanes and failed Session records.
_Avoid_: provider page, tool detail

**Workspace Catalog**:
The browseable read model Nexus uses to assemble Workspace Overview and Provider Detail state for Workspace-first navigation.
_Avoid_: cache blob, sidebar data

**Approval Request**:
A Session event that asks Nexus to collect an allow-or-deny decision for provider work before it continues.
_Avoid_: auth prompt, provider popup

**Session Surface**:
The primary product-visible way Nexus presents and interacts with a Session, such as a terminal view or a structured activity view.
_Avoid_: provider mode, renderer

**Session Surface Support**:
The status of whether a specific Nexus client can present and operate a Session's primary Session Surface.
_Avoid_: Provider Capability, launchability

**Session Presentation**:
A client-side projection of a Session's primary Session Surface into shared render-ready state that platform-specific UI adapters consume.
_Avoid_: view model, renderer helper, UI helper

**Workspace Availability**:
The status of whether a Workspace's target location is currently accessible and usable.
_Avoid_: host validation, provider health

**Unavailable Workspace**:
A Workspace whose target cannot currently be used because of transient environmental conditions.
_Avoid_: broken workspace

**Broken Workspace**:
A Workspace whose saved target or configuration needs repair before it can be used.
_Avoid_: unavailable workspace

**Unavailable Host**:
A Host whose remote execution target cannot currently be reached or used because of transient conditions.
_Avoid_: broken host

**Broken Host**:
A Host whose saved connection target or configuration needs repair before it can be used.
_Avoid_: unavailable host

**Blocked Check**:
A status meaning Nexus could not perform a check because an upstream dependency failed or was unavailable.
_Avoid_: unavailable, misconfigured

**Detach**:
Ending Nexus's active attachment to a Session without terminating the Session runtime.
_Avoid_: stop, close

## Relationships

- A **Workspace** contains one or more **Sessions**
- A **Provider** can be used in many **Workspaces**
- A **Session** belongs to exactly one **Workspace** and one **Provider**
- A **Default Session** is a **Session**
- A **Named Session** is a **Session**
- A **Workspace** and **Provider** pair has exactly one conceptual **Default Session** lane
- Deleting a **Default Session Record** does not remove the conceptual **Default Session** lane for its **Workspace** and **Provider**
- A **Workspace** and **Provider** pair may have many **Named Sessions**
- A **Workspace Overview** belongs to exactly one **Workspace**
- A **Provider Detail** belongs to exactly one **Workspace** and one **Provider**
- A **Session** may be **Detached** without being stopped
- A **Session** has exactly one **Session Record** in Nexus persistence
- A **Session** has at most one **Controller** at a time
- A **Session** may have many **Viewers** at the same time
- A **Remote Client** may attach to a **Session** as its **Controller** or as a **Viewer**
- A successful **Pairing** allows a **Remote Client** to reconnect without repeating the first-time trust ceremony
- A successful **Pairing** authorizes a **Paired Device** against its **Paired Mac** as a whole rather than per Workspace or per Provider
- A **Remote Client** may trust many **Paired Macs** over time
- A **Paired Mac** may trust many **Paired Devices** over time
- **Remote Access** may be enabled or disabled on a **Paired Mac**
- A **Workspace** has exactly one **Workspace Target**
- Changing a **Remote Workspace** target creates a new **Remote Workspace** rather than mutating the existing one
- A **Host** can be referenced by many **Remote Workspaces**
- A **Host** has one current **Host Validation** state
- A **Workspace** has one current **Workspace Availability** state
- An **Unavailable Workspace** differs from a **Broken Workspace** by whether the problem is transient or requires configuration repair
- An **Unavailable Host** differs from a **Broken Host** by whether the problem is transient or requires configuration repair
- A **Workspace Availability** check or **Provider Health** check may end in a **Blocked Check** when an upstream dependency fails
- A **Remote Workspace** uses one **Remote Session Strategy** when launched remotely
- A **Provider** has a separate **Provider Health** state for each Workspace target
- A **Provider** exposes one or more **Provider Capabilities** for a specific **Workspace** target
- A **Session** may emit zero or more **Approval Requests** while work is in progress
- A **Session** always has one primary **Session Surface** and may expose additional secondary interaction capabilities
- A **Session** always has a canonical shared activity stream regardless of its **Session Surface**
- A **Session Surface** may have different **Session Surface Support** on different Nexus clients
- A **Session Presentation** belongs to one client's projection of one **Session** primary **Session Surface**
- The same **Provider** may expose different **Session Surfaces** on different **Workspace Targets** or runtimes
- A remote **Provider Health** check resolves the **Provider** from the **Host** user's shell environments and records an absolute executable path for launch

## Example dialogue

> **Dev:** "If I have the same codebase on my Mac and on a server, is that one Workspace or two?"
> **Domain expert:** "Two - a local **Workspace** and a **Remote Workspace** are separate because their execution state and health are different."

## Flagged ambiguities

- "remote" was being used to mean both a **Remote Workspace** and remote control from iOS - resolved: a **Remote Workspace** is an execution target; a **Remote Client** is a separate client capability.
- "handoff" could imply bilateral approval between devices - resolved: a viewer may take **Controller** status without approval from the current controller, and local Mac input automatically reclaims **Controller** status.
- "remote access" could sound always-on - resolved: **Remote Access** is an explicit opt-in capability on a Mac and only works while Nexus is running.
- **Pairing** scope could be read as per-Workspace or per-Provider approval - resolved: a trusted **Paired Device** is authorized against the **Paired Mac** as a whole in V1.
- "tmux" could sound like a workspace type - resolved: it is a **Remote Session Strategy**.
- "tmux" could also be mistaken for the protocol transport or the visible **Session Surface** for remote protocol-native work - resolved: it is only the durability mechanism behind a remote **Session**, while the protocol transport and primary **Session Surface** are separate concerns.
- "remote health" was too vague - resolved: split into **Host Validation** and **Provider Health**.
- User-installed provider CLIs may appear in one Host shell environment but not another, and may not appear in the raw SSH command PATH at all - resolved: terminal-backed remote **Provider Health** resolves executables across the Host user's shell environments and standard per-user install locations, then remote launch uses that absolute path.
- Remote path accessibility is not **Host Validation** - resolved: it belongs under **Workspace Availability**.
- Service restart semantics are not uniform across targets - resolved: local session runtime may be lost after service restart, while tmux-backed remote Sessions are recoverable.
- A failed dependency is not the same as a failed check - resolved: use **Blocked Check** for checks that could not run because an upstream dependency failed.
- "stop" and "detach" are not synonyms - resolved: **Detach** leaves runtime alive; stop terminates runtime.
- "delete session" could imply killing a live runtime - resolved: **Delete Session Record** removes Nexus persistence only and is allowed only when the Session is not running.
- deleting a **Default Session Record** could imply removing the default lane itself - resolved: the persisted record is deleted, but the conceptual **Default Session** lane remains for that **Workspace** and **Provider**.
- "unavailable" and "broken" are not synonyms for a **Workspace** - resolved: unavailable means transient environment failure; broken means saved target/configuration requires repair.
- The same unavailable/broken distinction applies to a **Host** - resolved: unavailable means transient reachability/auth environment failure; broken means the saved Host target/configuration needs repair.
- A **Workspace** target is not always a folder path - resolved: use **Workspace Target** for the local-folder vs Host-plus-remote-path distinction.
- Changing a **Remote Workspace** Host or remote path is not a small edit - resolved: it creates a new **Remote Workspace** because the **Workspace Target** changed.
- "alternate session" is vague product language - resolved: use **Named Session** for additional explicitly created Session lanes distinct from the **Default Session**.
- "operable provider" was vague product language - resolved: use **Launchable Provider** when the issue is whether Nexus can start a **Session** now, based on current **Provider Health**.
- Shared UI affordances should not infer action support from provider names alone - resolved: expose **Provider Capability** from the service rather than hardcoding Claude-specific checks in the UI.
- Action support and launch readiness are different questions - resolved: **Provider Capability** explains whether Nexus supports an action on a target, while **Provider Health** explains whether it can succeed now.
- **Provider Capability** could be mistaken for client UI support - resolved: **Provider Capability** stays Workspace-target-scoped, while **Session Surface Support** describes whether a client can present and operate a Session's primary **Session Surface**.
- "session" could be mistaken for a terminal runtime - resolved: a **Session** is a provider-managed workstream; terminal I/O is only one possible presentation.
- provider-native words like "thread" or "conversation" could leak into product language - resolved: Nexus keeps **Session** as the public concept and stores provider-native identifiers as adapter details.
- a **Provider** identity could be mistaken for a fixed UI shape - resolved: **Session Surface** is chosen per Session/runtime context, so the same **Provider** may appear through different surfaces.
- **Session Surface** could be mistaken for an exclusive all-or-nothing mode - resolved: a **Session** has one primary **Session Surface** and may still expose secondary capabilities.
- **Session Surface Support** could be mistaken for provider-specific branding rules - resolved: when a client supports a primary **Session Surface**, that support applies across all launchable **Sessions** using that surface unless a separate product limit says otherwise.
- **Session Surface Support** could be mistaken for current write authority - resolved: it describes whether a client can present and operate a surface type at all, while **Controller** vs **Viewer** decides whether that attached client may perform Session-writing actions right now.
- approvals could be confused with provider login or auth - resolved: **Approval Request** is Session-time control over provider work, while provider authentication remains provider-native readiness/auth state.
- "send input" could be mistaken for terminal keystrokes only - resolved: the **Controller** owns all Session-writing actions, including structured prompts and **Approval Request** decisions.
- **Controller** could be mistaken for always owning a visible terminal-size concept - resolved: for structured **Sessions**, **Controller** is still the writer-authority concept; any viewport mechanics are implementation details rather than product language.
- "live Session" could be mistaken for a continuously running provider process - resolved: a **Session** is the provider-managed workstream and may remain usable through provider-native continuity even when Nexus relaunches the Provider between prompts.
- **Ready Session** could be mistaken for a Session with a continuously attached provider runtime - resolved: ready means Nexus can use the Session now, including Session models that resume provider work on demand from stored provider-native continuity.
- **Remote Session Strategy** could be mistaken for a guarantee that every ready remote **Session** keeps a continuously attached runtime - resolved: some remote structured **Sessions** may stay **ready** through stored provider-native continuity and persisted history while no live remote runtime is attached; the strategy governs durability only while remote runtime work is active.
- "launch" could be mistaken for always starting a continuously attached provider runtime - resolved: for on-demand structured **Sessions**, launch/create may open a ready **Session Record** first, and the first explicit prompt starts provider-native runtime work.
- Grok-style "Reasoning / Tools / Final Answer" could be mistaken for markdown inside one assistant **message** only - resolved: **Session Presentation** builds **Agent Turn Presentation** primarily from the canonical activity stream and **Provider** events (event-native), with optional text-section parsing only when a **Provider** emits a single formatted assistant blob (hybrid). Rollout order: Pi, then Codex, then IBM Bob.
- **Agent Turn** boundaries could be mistaken for only `isAgentTurnInProgress` or only provider `turn_end` - resolved: **hybrid** boundaries. Persisted and paged history group turns from **prompt-anchored** user **message** rows (`prompt` set or canonical user prefix). The live tail attaches in-progress assistant draft and in-flight tool output to the **open** turn while agent work is active. Layout is a **turn stack** after each user bubble: Reasoning, Tools, then final assistant answer.
- Agent turn UI could be done by visually grouping flat **activity** rows in one client only - resolved: **Session Presentation** emits composite **feed segments** (e.g. user message, agent turn stack, standalone rows outside the stack). Clients iterate one `LazyVStack` (or equivalent) child per segment; reasoning and tool rows are not separate scroll items in the feed projection. Canonical **activity** stream on **SessionScreen** stays complete for persistence and paging.
- Rows between user prompt and assistant answer could all be folded into one accordion - resolved: **split** placement. **Reasoning** accordion: `status` items whose text is the canonical thoughts label (`thoughts:`). **Tools** accordion: tool-execution `command` rows (and errors tied to that execution), including nested subagent assistant text as output of the parent tool call-not the turn's **Final answer**. **Final answer**: the primary assistant `message` for that turn (e.g. provider-prefixed main reply), including streaming draft on the open turn. **Outside the stack**: user-initiated slash echoes, session lifecycle status, compaction/retry banners, and similar; optional **Activity** accordion later for non-slash agent-time noise between anchor and answer.
- **Tools** disclosure defaults could mirror ChatGPT Agent mode literally - resolved: turn-level **Tools** accordion **collapsed by default**; header summary **"Used N tools"**; each per-tool row **collapsed by default** with **tool name plus one-line argument preview**. Tool body shows **structured fields** (call, result, error) in **Session Presentation**; optional **View raw JSON** toggle exposes raw payload when the screen still has provider event or activity detail text-not required when history paging no longer carries events.
- Pi **thoughts:** status rows could stay separate feed cards or plain-only — resolved: **Reasoning** accordion (header label **Reasoning**), body rendered with **StructuredSessionMarkdownText**; multiple thoughts blocks in one **Agent Turn** merge into one accordion with separators. **Collapsed** after the turn completes; **expanded or live-streaming** while the turn is in progress.
- Pi v1 scope for agent response formatting could include images, artifacts, and haptics in one slice — resolved: **stack + rich markdown** (composite feed segments, Reasoning/Tools/Final answer accordions, existing feed markdown policies on assistant text, plus **KaTeX/LaTeX** in the shared markdown path for macOS and iOS). Images/carousel, artifact preview cards, and completion haptics are follow-up slices unless explicitly pulled in.
- Turn-stack UI could ship on iOS before macOS — resolved: **same slice** for Pi v1. Composite feed segments and turn-stack adapters land together on **Remote Client** and macOS structured feed so **Session Presentation** has one shape and clients stay in parity.
- KaTeX/LaTeX could mean one renderer for feed and reader — resolved: **hybrid math**. **Display math** (`$$…$$` and equivalent display blocks) in Pi v1 first ship; **inline** math (`$…$`) is a follow-up. **Full-response reader** (MarkdownUI-backed) gets display math first; structured **feed** keeps the lightweight **AttributedString** path with **plain fallback** for unsupported math until a deferred math sub-slice; math-heavy bodies can still use the reader. Respect existing feed markdown hydration and scroll-idle policies on iOS when adding display math blocks.
- Syntax-highlighted code blocks with copy could require MarkdownUI for the whole feed — resolved: **extend the lightweight feed renderer**. Detect fenced code in markdown and render **custom SwiftUI blocks** (monospace, copy, lightweight highlight) in **Final answer** and **Reasoning** on the feed; **MarkdownUI** remains the rich surface for the full-response reader. Do not move the entire lazy feed to MarkdownUI for Pi v1.
- **Thinking…** chrome could duplicate an expanded **Reasoning** accordion — resolved: **no duplicate spinners**. Use the global thinking affordance only until the open turn has reasoning content; then hide it and show the **Reasoning** accordion (expanded or streaming). If agent work is in progress with no thoughts yet, show a single lightweight **Thinking…** state tied to the open **Agent Turn** (not a second parallel progress UI).
- **Approval Request** UI could nest inside **Agent Turn** narration — resolved: keep approvals **outside** the turn stack in **session chrome** (pinned above the composer / existing approval affordances). Approvals are Session control, not Reasoning/Tools/Final answer content; presentation continues to suppress redundant thinking chrome when approvals are pending.
- Disclosure expansion state could reset on every scroll or persist forever — resolved: **per-turn sticky** for the lifetime of the attached **Session**. User overrides to Reasoning/Tools on completed turns are remembered by stable **Agent Turn** identity in client state; defaults apply again on detach, relaunch, or new attachment—not written to **Session Record** persistence.