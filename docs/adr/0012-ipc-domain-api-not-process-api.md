# ADR 0012: Local IPC domain API is workspace/provider/session-first, not process-first

## Status
Accepted

## Decision
The service API is expressed in Nexus domain concepts rather than raw process or PTY primitives.

## Consequences
Clients request workspace, provider, session, and terminal operations without directly orchestrating low-level runtime objects.
