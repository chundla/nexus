# ADR 0004: SQLite/custom store owned by the Background Service

## Status
Accepted

## Decision
Persistent Nexus metadata is stored in a SQLite-backed custom store owned by the Background Service.

## Consequences
Persistence is independent of the SwiftUI app. Milestone one stores metadata, not full local PTY runtime state.
