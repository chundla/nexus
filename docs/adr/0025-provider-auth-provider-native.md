# ADR 0025: Provider authentication remains provider-native; Nexus only performs light auth-readiness detection

## Status
Accepted

## Decision
Providers own their own authentication flows. Nexus performs only light auth-readiness detection where feasible.

## Consequences
Interactive auth remains terminal-native and provider-specific integration risk stays low.
