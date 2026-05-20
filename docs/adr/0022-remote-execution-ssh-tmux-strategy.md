# ADR 0022: Remote execution uses SSH transport, with tmux as a session strategy rather than a separate workspace type

## Status
Accepted

## Decision
Remote execution uses SSH. tmux is an optional session persistence strategy, not a distinct workspace type.

## Consequences
Remote modeling stays centered on Host, Workspace, and Session strategy.
