# ADR 0001: Background Service is the source of truth

## Status
Accepted

## Decision
The macOS Background Service is the authoritative owner of Nexus state and runtime orchestration.

## Consequences
The service owns persistence, workspace groups, workspaces, provider config and health, sessions, launch snapshots, and terminal session ownership. The macOS app is a client, not the authority.
