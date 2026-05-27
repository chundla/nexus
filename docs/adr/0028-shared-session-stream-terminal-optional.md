# ADR 0028: Shared Session stream is canonical; terminal is an optional Session surface

## Status
Accepted

Nexus will treat a **Session** as a provider-managed workstream rather than a universal terminal runtime. The Background Service owns a shared Session stream for messages, **Approval Requests**, progress, diffs, command activity, and completion state, while terminal input/output remains an optional surface for Providers that expose one. This supersedes ADR 0007 because protocol-native integrations such as Pi RPC and future Codex app-server support need app-native flows that are richer than a PTY-only model, and Nexus must support terminal-backed and protocol-native Session runtimes side-by-side during migration.
