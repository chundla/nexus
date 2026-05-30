# ADR 0034: Provider Modules are the single Provider seam

## Status
Accepted

Nexus now has terminal-backed, structured, remote-recoverable, and ready-without-runtime **Sessions** across Claude, Codex, Pi, and IBM Bob, so each **Provider** will have one service-owned **Provider Module** seam that owns **Provider Health**, catalog results and text, **Session** transition planning, and runtime construction using shared runtime **Adapter** implementations. Shared modules keep **Workspace Target** checks, persistence writes, and live runtime registration, but `ServiceProviderAdapter`, split Provider seams, and a lasting generic fallback are rejected because they keep Provider policy shallow, leak rules into `WorkspaceCatalog` and lifecycle code, and reduce **locality**.