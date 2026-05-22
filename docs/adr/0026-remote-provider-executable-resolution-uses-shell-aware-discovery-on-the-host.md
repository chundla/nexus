# ADR 0026: Remote provider executable resolution uses shell-aware discovery on the Host

## Status
Accepted

## Decision
For a Remote Workspace, Nexus resolves provider executables by checking the Host user's shell environments, preferring the configured shell first and then falling back across common shells and standard per-user install locations. Nexus records the absolute executable path it finds and uses that path for remote launch instead of assuming a system-wide install location.

## Consequences
Per-user installs such as `~/.local/bin`, `~/bin`, and version-manager-managed CLIs are supported without requiring root-owned symlinks or system-wide packaging. This is more resilient when a Host's configured shell and the shell-specific startup files that expose provider CLIs are not perfectly aligned.
