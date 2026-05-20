# ADR 0009: Session launch config is snapshotted at creation time

## Status
Accepted

## Decision
Each session stores an immutable resolved launch snapshot at creation time.

## Consequences
Later configuration changes affect future launches only, not existing sessions.
