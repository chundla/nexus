# ADR 0024: SSH authentication reuses the user’s existing SSH configuration and agent; Nexus does not manage SSH secrets in V1

## Status
Accepted

## Decision
Nexus reuses the user's existing SSH tooling and configuration and does not manage raw SSH secrets in V1.

## Consequences
Remote access aligns with standard SSH workflows and avoids an early secret-management burden.
