# ADR 0005: Provider adapters live entirely in the Background Service

## Status
Accepted

## Decision
Provider detection, health checks, launch semantics, and attach/resume behavior live in the Background Service.

## Consequences
The UI renders provider state and invokes actions but does not duplicate adapter logic.
