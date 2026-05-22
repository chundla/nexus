# ADR 0026: Remote provider executable resolution uses the Host user's login-shell environment

## Status
Accepted

## Decision
For a Remote Workspace, Nexus resolves provider executables from the Host user's login-shell environment, records the absolute executable path, and uses that path for remote launch instead of assuming a system-wide install location.

## Consequences
Per-user installs such as `~/.local/bin`, `~/bin`, and version-manager-managed CLIs are supported without requiring root-owned symlinks or system-wide packaging.
