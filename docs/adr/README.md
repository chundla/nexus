# Architecture Decision Records

These ADRs capture durable decisions for Nexus.

Numbering starts at `0001`.

Initial set:

1. Background Service is the source of truth
2. Workspace-first product model
3. Real local IPC from day one
4. SQLite/custom store owned by the Background Service
5. Provider adapters live entirely in the Background Service
6. Separate local and remote workspaces
7. Shared terminal session model with platform-specific rendering
8. Workspace groups are first-class, with one primary group per workspace in V1
9. Session launch config is snapshotted at creation time
10. Service restart does not restore live local PTY runtime in milestone one
11. Default session reuse for workspace+provider, with optional additional named sessions
12. Local IPC domain API is workspace/provider/session-first, not process-first
13. Workspace overview is provider-first inside a workspace
14. Quick switch is workspace-first, with provider/session results as secondary
15. Provider health contract requires executable resolution, version check when possible, and basic launchability probe
16. Session stop and record deletion are separate actions
17. Failed launches create inspectable failed session records
18. Terminal sessions support one controller and multiple viewers
19. Terminal transcript capture is configurable, with bounded scrollback always available
20. iOS acts as a remote client to the macOS Background Service, not an independent local execution host
21. V1 iOS/macOS pairing is local-network only with durable device pairing
22. Remote execution uses SSH transport, with tmux as a session strategy rather than a separate workspace type
23. Remote hosts are first-class saved profiles, not just fields embedded in workspaces
24. SSH authentication reuses the user’s existing SSH configuration and agent; Nexus does not manage SSH secrets in V1
25. Provider authentication remains provider-native; Nexus only performs light auth-readiness detection
26. Remote provider executable resolution uses the Host user's login-shell environment
