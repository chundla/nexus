# Pi RPC (Nexus)

Nexus runs Pi in headless **RPC mode** (`pi --mode rpc`) for structured **Sessions**. The Background Service owns the JSONL protocol on stdin/stdout via `PiRPCSessionRuntime` in `Modules/Sources/NexusService`.

## Canonical protocol reference

The wire format, commands, events, and extension UI sub-protocol are defined in the **Pi coding agent** package:

- Installed pi: `$(dirname $(which pi))/../lib/node_modules/@earendil-works/pi-coding-agent/docs/rpc.md`
- Or read `docs/rpc.md` in `@earendil-works/pi-coding-agent` on npm.

Nexus does not fork that document; treat it as the source of truth for Pi behavior.

## Nexus lifecycle mapping

| Pi RPC | Nexus user prompt (“Thinking…”) |
|--------|----------------------------------|
| `prompt` accepted | `promptTurnCommitted` set when a new turn is sent; cleared if `response.success == false` |
| Assistant `message_end` / `message_update` (`done` / `error`) | Provisional `Pi:` rows; `toolUse` keeps prompt open |
| `turn_end` | Clears streaming buffers only; does **not** end the user prompt |
| `agent_end` (`willRetry != true`) | Ends user prompt; final assistant from `messages[]` when needed |
| Process exit with open prompt | Turn aborted |
| `get_state.isStreaming == false` while prompt open | Reconciled on automatic `get_session_stats` (after `turn_end` / `agent_end` paths) |
| No RPC stdout progress for 90s while prompt open | Turn watchdog polls `get_state` / `get_session_stats`, then surfaces a provider stall error and ends the turn |

Watchdog tuning (macOS service / Xcode Run env): `NEXUS_PI_RPC_TURN_STALL_SEC` (default 90), `NEXUS_PI_RPC_TURN_POLL_SEC` (default 15), `NEXUS_PI_RPC_TURN_WATCHDOG_TICK_SEC` (default 5). Optional startup stats: `NEXUS_PI_RPC_STARTUP_SESSION_STATS=1`.

Intermediate `turn_end` events are expected during multi-tool runs; only **`agent_end`** completes the user-visible turn (see ADR 0028 shared Session stream).

## Framing

Nexus splits stdout on `\n` only and strips trailing `\r`, matching Pi’s JSONL rules (do not use Node `readline`).

## Related

- ADR 0028: shared Session stream; terminal optional
- `docs/architecture/milestone-8.md`: local Pi RPC adapter