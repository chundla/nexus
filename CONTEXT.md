# Nexus

Nexus is a workspace-first control center for coding agent CLIs across local and remote environments. This context captures the product language that should stay stable as the implementation grows.

## Language

**Workspace**:
A named working target that Nexus manages for launching and resuming provider sessions.
_Avoid_: project, repo

**Provider**:
A supported coding CLI integration that can be used inside a Workspace.
_Avoid_: tool, backend

**Session**:
An app-owned workstream for one Provider in one Workspace.
_Avoid_: process, tab

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

**Host Validation**:
The status of whether Nexus can reach and authenticate to a Host and verify required remote execution capabilities.
_Avoid_: provider health, remote health

**Provider Health**:
The status of whether a Provider is available and launchable for a specific Workspace target. For a **Remote Workspace**, this resolves the Provider from the Host user's shell environments, records an absolute executable path, and then launches by absolute path.
_Avoid_: host status, remote health

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
- A **Session** may be **Detached** without being stopped
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
- A remote **Provider Health** check resolves the **Provider** from the **Host** user's shell environments and records an absolute executable path for launch

## Example dialogue

> **Dev:** "If I have the same codebase on my Mac and on a server, is that one Workspace or two?"
> **Domain expert:** "Two — a local **Workspace** and a **Remote Workspace** are separate because their execution state and health are different."

## Flagged ambiguities

- "remote" was being used to mean both a **Remote Workspace** and remote control from iOS — resolved: a **Remote Workspace** is an execution target; iOS remote control is a separate client capability.
- "tmux" could sound like a workspace type — resolved: it is a **Remote Session Strategy**.
- "remote health" was too vague — resolved: split into **Host Validation** and **Provider Health**.
- User-installed provider CLIs may appear in one Host shell environment but not another, and may not appear in the raw SSH command PATH at all — resolved: remote **Provider Health** resolves executables across the Host user's shell environments and standard per-user install locations, then remote launch uses that absolute path.
- Remote path accessibility is not **Host Validation** — resolved: it belongs under **Workspace Availability**.
- Service restart semantics are not uniform across targets — resolved: local session runtime may be lost after service restart, while tmux-backed remote Sessions are recoverable.
- A failed dependency is not the same as a failed check — resolved: use **Blocked Check** for checks that could not run because an upstream dependency failed.
- "stop" and "detach" are not synonyms — resolved: **Detach** leaves runtime alive; stop terminates runtime.
- "unavailable" and "broken" are not synonyms for a **Workspace** — resolved: unavailable means transient environment failure; broken means saved target/configuration requires repair.
- The same unavailable/broken distinction applies to a **Host** — resolved: unavailable means transient reachability/auth environment failure; broken means the saved Host target/configuration needs repair.
- A **Workspace** target is not always a folder path — resolved: use **Workspace Target** for the local-folder vs Host-plus-remote-path distinction.
- Changing a **Remote Workspace** Host or remote path is not a small edit — resolved: it creates a new **Remote Workspace** because the **Workspace Target** changed.