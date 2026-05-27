# ADR 0030: Provider-native continuation linkage lives on the Session Record, not the Launch Snapshot

## Status
Accepted

Nexus now has multiple protocol-native **Providers** that need continuation metadata across relaunch, so provider-native linkage is stored as generic mutable adapter metadata on the **Session Record** rather than inside the immutable **Launch Snapshot**. This keeps launch configuration snapshotted at creation time while allowing Pi and Codex to preserve **Session** continuity across relaunch and service restart without creating provider-specific persistence silos.
