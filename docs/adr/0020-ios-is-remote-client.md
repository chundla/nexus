# ADR 0020: iOS acts as a remote client to the macOS Background Service, not an independent local execution host

## Status
Accepted

## Decision
iOS remotely controls Mac-managed sessions and does not independently host local coding CLI execution.

## Consequences
macOS remains the execution authority; iOS is built around pairing, attachment, and remote control.
