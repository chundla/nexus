# ADR 0031: Remote protocol-native Sessions use a service-owned SSH stdio bridge with tmux durability

## Status
Accepted

Nexus now needs remote protocol-native **Sessions** in addition to terminal-backed remote **Sessions**, so the **Background Service** will own one live remote protocol bridge per **Session** to a provider process running on the **Host** over raw SSH stdio without PTY allocation. **tmux** remains only the **Remote Session Strategy** for durability across detach and restart, generic remote runtime recovery state stays service-owned, and provider-native continuity such as Codex thread linkage stays on the **Session Record**; this keeps transport, durability, and provider-native continuation as separate concerns and leaves the remote protocol-native seam provider-neutral.
