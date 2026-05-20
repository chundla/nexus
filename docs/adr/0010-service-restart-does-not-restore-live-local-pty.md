# ADR 0010: Service restart does not restore live local PTY runtime in milestone one

## Status
Accepted

## Decision
If the Background Service restarts, live local PTY/process runtime is not restored in milestone one.

## Consequences
Session metadata survives, but affected local sessions become lost/interrupted and relaunchable rather than reattachable.
