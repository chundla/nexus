# ADR 0015: Provider health contract requires executable resolution, version check when possible, and basic launchability probe

## Status
Accepted

## Decision
Every provider adapter implements a minimum health contract: executable resolution, version detection when possible, a lightweight launchability probe, and structured diagnostics.

## Consequences
Provider cards can present consistent health information across supported CLIs.
