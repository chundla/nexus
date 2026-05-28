# Local structured Sessions may be ready without a continuously attached provider runtime

Nexus now supports local structured **Sessions** whose provider-native continuity can be resumed on demand, so a **Session** may remain **ready** and inspectable even when no live provider process is currently attached. This keeps **Session** state tied to whether Nexus can use the **Session** now rather than to continuous process liveness, and it allows Bob-style on-demand local structured runtimes without breaking shared stop, delete, relaunch, and multi-client observation semantics.
