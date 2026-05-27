# ADR 0029: Session surface is explicit, and client support is separate from Provider Capability

## Status
Accepted

Nexus now supports the same **Provider** exposing different primary **Session Surfaces** on different **Workspace Targets** and runtimes, so the shared `SessionScreen` contract must carry primary **Session Surface** explicitly rather than asking clients to infer it from provider identity. **Provider Capability** remains **Workspace**-target-scoped, while client ability to present and operate that surface is modeled separately as **Session Surface Support**, because clients such as iPhone may inspect a **Session** they cannot yet fully operate.
