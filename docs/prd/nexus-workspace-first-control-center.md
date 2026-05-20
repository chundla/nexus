## Problem Statement

Developers who use multiple coding agent CLIs do not have a single workspace-centric control center for launching, resuming, switching, and managing those tools across their projects. Today they must remember per-tool commands, per-project locations, separate session histories, and different local versus remote execution contexts. This makes it slow and error-prone to move between Workspaces, compare Providers, recover failed launches, and maintain continuity across coding tasks.

For Nexus specifically, the problem is larger than launching a single CLI. Users need one place to organize many Workspaces, see which Providers are available in each Workspace, resume the right Session quickly, and eventually remote-control those Sessions from iOS through the macOS Background Service.

## Solution

Nexus will provide a workspace-first control center for coding agent CLIs across local and remote environments.

From the user’s perspective, Nexus will let them:

- organize Workspaces into Workspace Groups
- open a Workspace and see all supported Providers in one provider-first overview
- launch or resume the default Session for a Workspace + Provider pair
- create additional named Sessions when needed
- switch quickly among Workspaces, Providers, and active Sessions
- inspect Provider Health before launching
- understand whether a Workspace is available or broken
- inspect failed launches as first-class Session records rather than transient errors
- use a focused terminal-first Session screen while keeping the workspace-first model intact

Milestone one focuses on macOS with a Background Service as the source of truth, local Workspaces only, real local IPC, and one initial Provider adapter chosen by implementation leverage.

## User Stories

1. As a developer, I want Nexus to organize my coding work around Workspaces, so that I can think in terms of projects rather than individual CLI tools.
2. As a developer, I want to organize Workspaces into Workspace Groups, so that I can manage many repositories and projects coherently.
3. As a developer, I want each Workspace to have a stable identity independent of its display name, so that Nexus can preserve history and relationships even if I rename things.
4. As a developer, I want to add a local Workspace by choosing a folder, so that I can start using Nexus without manual command entry.
5. As a developer, I want Nexus to assign a new Workspace to a default Workspace Group automatically when appropriate, so that creation stays fast.
6. As a developer, I want Nexus to ask me which primary Workspace Group to use when multiple groups exist, so that my Workspace organization remains intentional.
7. As a developer, I want to see a Workspace overview before entering a Session, so that I can understand the Workspace’s state and choose the right Provider.
8. As a developer, I want the Workspace overview to be provider-first, so that I can immediately compare available coding CLIs inside a Workspace.
9. As a developer, I want Nexus to show all supported Providers in each Workspace, even when some are unavailable, so that I know what Nexus supports and what needs configuration.
10. As a developer, I want Provider cards to show whether a Provider is available, unavailable, misconfigured, or still being checked, so that I can make launch decisions confidently.
11. As a developer, I want Provider Health to include executable discovery, version, and launchability diagnostics, so that I can troubleshoot launch issues before opening a Session.
12. As a developer, I want Nexus to detect one implemented Provider first using the simplest viable adapter, so that the core architecture is proven before breadth is added.
13. As a developer, I want Nexus to track a last-used Provider per Workspace, so that common Workspace flows remain fast.
14. As a developer, I want selecting a Provider in a Workspace to reuse the default Session by default, so that I can continue work without spawning unnecessary Sessions.
15. As a developer, I want each Workspace + Provider pair to have a clear default Session, so that my primary path through Nexus stays predictable.
16. As a developer, I want to create additional named Sessions for the same Workspace and Provider, so that I can separate tasks like bugfixes, refactors, and experiments.
17. As a developer, I want extra Sessions to be optional rather than mandatory, so that the normal flow stays simple.
18. As a developer, I want additional Sessions to be auto-named initially but renameable later, so that I can organize them without added friction.
19. As a developer, I want Provider cards to show that alternate Sessions exist, so that I do not lose track of extra workstreams.
20. As a developer, I want a Provider detail view within a Workspace, so that I can manage the default Session, alternate Sessions, and failed launches in one place.
21. As a developer, I want a focused Session screen for active work, so that I can interact deeply with a coding CLI without leaving Nexus.
22. As a developer, I want the Session screen to remain logically owned by the Workspace and Provider, so that Nexus stays workspace-first.
23. As a developer, I want the last active Session and basic viewing state to restore when I return, so that I can resume work quickly.
24. As a developer, I want one main Session view with fast switching instead of a complex tab system in milestone one, so that the app stays focused on orchestration rather than terminal multiplexing.
25. As a developer, I want the Background Service to own Session lifecycle and terminal state, so that UI lifetime does not determine whether my work continues.
26. As a developer, I want the macOS app to communicate with the Background Service over real local IPC, so that the service boundary is real from the start.
27. As a developer, I want the Background Service to be the source of truth for Workspace Groups, Workspaces, Provider configuration, Sessions, and Launch Snapshots, so that state stays consistent.
28. As a developer, I want Provider adapters to live in the Background Service, so that launch and health logic are authoritative and not duplicated in the UI.
29. As a developer, I want Session launch configuration to be snapshotted at creation time, so that existing Sessions do not silently change when configuration changes.
30. As a developer, I want failed launches to create inspectable failed Session records, so that failures are part of my operational history.
31. As a developer, I want failed Session records to include diagnostics and retry actions, so that I can recover without guesswork.
32. As a developer, I want to stop a Session separately from deleting its record, so that runtime control and history cleanup stay explicit.
33. As a developer, I want manual deletion of non-running Session records, so that I can clean up stale or failed Sessions.
34. As a developer, I want stopping a Session to use selective confirmation only when the risk is higher, so that common flows remain fast.
35. As a developer, I want a consistent Session lifecycle model across Providers, so that Nexus behavior stays predictable.
36. As a developer, I want Provider-specific diagnostics beneath a shared Session state model, so that Nexus can stay consistent without flattening away Provider differences.
37. As a developer, I want terminal interaction to be terminal-first rather than chat-first, so that Provider-native UX is preserved.
38. As a developer, I want a proven embedded terminal component on macOS, so that interactive CLI behavior remains faithful.
39. As a developer, I want bounded scrollback to be always available, so that I can review recent Session output reliably.
40. As a developer, I want transcript capture to be configurable, so that I can balance history, privacy, and storage concerns.
41. As a developer, I want Nexus to remember metadata about Sessions even if the app UI closes, so that I can resume my operational context.
42. As a developer, I want the Background Service to survive UI closure by design, so that my Sessions are not tied to the window lifecycle.
43. As a developer, I want a minimal Background Service status area in milestone one, so that I can see whether Nexus’s execution authority is healthy.
44. As a developer, I want a minimal diagnostics and log view, so that I can troubleshoot service issues, launch failures, and Provider Health problems.
45. As a developer, I want quick switch to be workspace-first, so that search reinforces the primary mental model of Nexus.
46. As a developer, I want quick switch to include Provider and Session matches as secondary results, so that I can move quickly without losing the Workspace-first structure.
47. As a developer, I want the home experience to support recent activity while still centering Workspaces and Workspace Groups, so that frequent switching stays efficient.
48. As a developer, I want Workspace availability to be visible, so that I can distinguish healthy Workspaces from broken ones.
49. As a developer, I want broken Workspaces to remain visible and repairable rather than disappearing, so that I do not lose context or history.
50. As a developer, I want Nexus to support any local folder as a Workspace, so that I am not restricted to git repositories.
51. As a developer, I want git-aware Workspaces to show lightweight repository signals like branch and dirty state later in the product, so that I have useful context without turning Nexus into a git client.
52. As a developer, I want local and remote copies of the same project to remain separate Workspaces, so that execution state and health remain unambiguous.
53. As a developer, I want remote execution to use SSH later, so that Nexus fits standard developer infrastructure.
54. As a developer, I want tmux to be treated as a remote Session strategy rather than a different Workspace type, so that remote behavior remains understandable.
55. As a developer, I want remote Hosts to be first-class saved profiles, so that multiple remote Workspaces can share connection defaults and validation.
56. As a developer, I want Nexus to reuse my existing SSH configuration instead of managing secrets itself, so that remote access remains compatible with standard tooling.
57. As a developer, I want Provider authentication to remain Provider-native, so that Nexus preserves official auth flows rather than reimplementing them.
58. As a developer, I want the service API to operate in Nexus concepts like Workspace, Provider, and Session rather than PTY primitives, so that clients stay simple and stable.
59. As a developer, I want the service persistence layer to be service-owned and independent of SwiftUI assumptions, so that Nexus can grow beyond the starter template cleanly.
60. As a developer, I want the metadata store to preserve Workspace Groups, Workspaces, Session records, Launch Snapshots, Provider configuration, Provider Health, and recents, so that Nexus can rebuild its app state reliably.
61. As a developer, I want milestone one to treat live local runtime as non-restorable across service restarts, so that Nexus makes honest guarantees.
62. As a developer, I want interrupted local Sessions after a service restart to remain visible and relaunchable, so that recovery is explicit.
63. As a developer, I want the codebase to be split into deep modules for app UI, service runtime, shared domain, and IPC, so that each layer can evolve and be tested in isolation.
64. As a developer, I want the Background Service orchestration logic to be a deep module with a narrow interface, so that Provider launch and Session lifecycle complexity are encapsulated.
65. As a developer, I want launch configuration resolution to be a deep module, so that layered configuration can remain testable and stable as scope grows.
66. As a developer, I want Provider Health evaluation to be a deep module, so that Provider status remains consistent across Workspaces and future Hosts.
67. As a developer, I want Session lifecycle state transitions to be a deep module, so that the UI can react to a stable behavioral contract.
68. As a developer, I want terminal attachment and event streaming to be a deep module, so that future macOS and iOS clients can share one session model.
69. As a future iOS user, I want iOS to act as a remote client to the macOS Background Service, so that I can control Mac-managed Sessions from my phone later.
70. As a future iOS user, I want pairing to be local-network-only with durable trust in V1, so that remote control is secure without requiring cloud infrastructure.
71. As a future multi-client user, I want the terminal model to support one controller and multiple viewers, so that remote attachment can work without input conflicts.
72. As a maintainer, I want the architecture captured in ADRs and architecture docs, so that implementation work stays aligned with the product decisions already made.
73. As a maintainer, I want milestone-one scope documented clearly, so that implementation can reject accidental scope creep.
74. As a maintainer, I want module responsibilities documented up front, so that early code moves do not reintroduce UI-owned state.
75. As a maintainer, I want testing to focus on externally visible behavior at module boundaries, so that implementation refactors do not cause brittle failures.

## Implementation Decisions

- Nexus is a workspace-first control center for coding agent CLIs across local and remote environments.
- Milestone one is macOS-only in implementation, even though the long-term platform model includes iOS as a remote client.
- The Background Service is the source of truth for Workspace Groups, Workspaces, Provider configuration, Provider Health, Sessions, Launch Snapshots, persistence, terminal ownership, and diagnostics.
- The macOS app is a client/admin UI that must not become an implicit source of truth.
- The macOS app and Background Service communicate over real local IPC from day one.
- The local IPC API is domain-first and expressed in Workspace, Provider, Session, and terminal attachment concepts rather than process-first primitives.
- The codebase should be restructured immediately around core modules: NexusApp, NexusService, NexusDomain, and NexusIPC.
- Provider adapters live entirely inside NexusService.
- A future NexusProviders module is a likely extraction point once adapter complexity grows.
- A future NexusTerminal module is a likely extraction point once macOS and iOS both depend on a shared terminal model.
- The most important deep modules to build are:
  - service orchestration for Workspace/Provider/Session lifecycle
  - launch configuration resolution and Launch Snapshot generation
  - Provider Health evaluation
  - Session lifecycle state management
  - terminal session attachment/streaming model
  - service-owned metadata persistence
- Milestone one persistence is a SQLite-backed custom store owned by the Background Service.
- The metadata store persists Workspace Groups, Workspaces, Session records, Launch Snapshots, Provider configuration, Provider Health snapshots, default-session mappings, recent activity metadata, and diagnostics metadata.
- Live local PTY/process runtime state is not fully persisted in milestone one.
- If the Background Service restarts, live local Sessions become lost/interrupted and relaunchable rather than reattachable.
- Each Workspace has a stable internal identity and belongs to one primary Workspace Group in V1.
- The Workspace overview is provider-first.
- Provider cards show all supported Providers, not just detected ones.
- Milestone one supported Provider set is Codex, Claude, IBM Bob, and Pi at the product level, but only one Provider adapter needs to be implemented first, chosen by simplest practical launch path.
- Each Workspace + Provider pair has a default Session.
- Selecting a Provider in a Workspace reuses the default Session by default.
- Users can explicitly create additional named Sessions.
- Session launch configuration is snapshotted at Session creation time and does not inherit later config changes.
- Failed launches create inspectable failed Session records with diagnostics.
- Stop Session and Delete Record are separate actions.
- Session lifecycle uses a shared top-level state model with Provider-specific details beneath it.
- The terminal model is shared conceptually across platforms, but milestone one only implements macOS rendering.
- The macOS terminal should use a proven terminal component rather than a temporary console.
- Bounded scrollback is always available; full transcript capture is configurable.
- Quick switch is workspace-first, with Provider and Session matches as secondary results.
- Milestone one Workspace creation is local-only and uses a folder picker.
- Milestone one Workspace overview should show Workspace identity, primary group, local path, availability, Provider cards, default Session state, and compact alternate Session counts.
- Milestone one should include a Provider detail view containing the default Session, alternate Sessions, failed Session records, and Provider Health/diagnostics.
- Milestone one should include one focused Session screen with fast switching rather than a tab or pane system.
- The long-term remote model uses SSH transport, tmux as a Session strategy, first-class Host profiles, provider-native auth, and existing user SSH configuration.
- The long-term iOS model treats iOS as a remote client to the macOS Background Service with local-network-only durable pairing in V1.
- Existing ADRs and architecture documents are the governing source for these decisions.

## Testing Decisions

- Good tests should verify externally observable behavior and stable contracts rather than implementation details.
- Good tests should focus on domain transitions, persistence contracts, service API behavior, and adapter outputs rather than UI internals or private helper structure.
- The most important modules to test are the deepest modules with the narrowest interfaces:
  - NexusDomain state and identity rules
  - NexusService session orchestration and lifecycle transitions
  - launch configuration resolution and Launch Snapshot behavior
  - Provider Health evaluation and diagnostics behavior
  - service-owned metadata persistence
  - NexusIPC request/response and stream contract behavior
- Terminal tests should validate observable stream semantics and attachment behavior rather than the internal structure of the terminal renderer.
- Provider adapter tests should validate health contract behavior, launchability signaling, and structured diagnostics for the first implemented Provider.
- Session tests should cover default Session reuse, additional named Session creation, failed launch record creation, and loss semantics after service restart.
- Persistence tests should cover Workspace Group membership, Workspace identity, Session persistence, and immutable Launch Snapshot behavior.
- UI tests in milestone one should stay narrow and focus on critical behavior such as adding a Workspace, navigating to a Workspace overview, and launching/resuming a Session through the service boundary.
- Current prior art in the codebase is minimal because the repository is still a starter app with skeletal test targets, so this PRD expects the initial testing style and fixtures to be established as part of the architecture work.

## Out of Scope

- iOS target creation and implementation in milestone one
- remote SSH execution in milestone one
- tmux-backed remote Sessions in milestone one
- remote Host management UI in milestone one
- Provider installation and update management
- deep semantic normalization across Providers
- a custom chat-first interaction model
- editor integration or automatic opening of external editors
- multi-tab or pane-based terminal UX in milestone one
- full transcript retention policy management UI
- multi-client terminal control implementation in milestone one
- cloud relay, account system, or internet-wide pairing for iOS
- service restart recovery for live local PTY runtime in milestone one

## Further Notes

- Nexus already has architecture documentation and ADRs that define the product and technical direction; this PRD should be read as the product framing of those decisions.
- The immediate next implementation move after this PRD is to restructure the codebase into NexusApp, NexusService, NexusDomain, and NexusIPC before feature work expands.
- Milestone one is intentionally a vertical slice that proves the service-centered architecture using local Workspaces and one initial Provider adapter before broader Provider breadth, remote execution, and iOS control are added.
- The architecture intentionally favors deep modules with narrow, stable interfaces so that Provider breadth, SSH/tmux support, and iOS remote control can be layered in without rewriting the product spine.
