# ADR 0007: Shared terminal session model with platform-specific rendering

## Status
Accepted

## Decision
The Background Service owns canonical terminal session state. Clients render that shared model with platform-specific UI.

## Consequences
macOS and iOS can use different renderers while sharing attach, input, output, resize, and scrollback semantics.
