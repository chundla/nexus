# ADR 0003: Real local IPC from day one

## Status
Accepted

## Decision
The macOS app communicates with the Background Service over a real local IPC boundary from the start.

## Consequences
The UI cannot call service internals directly. The service boundary stays honest and can later be adapted for remote clients.
