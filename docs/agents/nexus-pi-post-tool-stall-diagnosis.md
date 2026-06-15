# Diagnosing Nexus-only Pi post-tool stalls

Symptom: from Nexus, `lets perform a code review on nexus` often stops after ~3 parallel tools — jsonl mtime frozen, Pi child at 0% CPU, no `agent_end` on RPC stdout, UI stuck on Thinking… Standalone `pi --mode rpc` / TUI / harness often completes.

## Phase 1 — Feedback loops (use all that apply)

### A. Differential exit codes (fastest)

```bash
./scripts/diagnose-pi-rpc-nexus-vs-baseline.sh
```

Runs the same prompt under **baseline** (script env), **nexus-shell-env** (merged login-shell env like `LocalShellEnvironmentResolver`), and optional **record** mode. Compare: baseline `0` + nexus-env `4/5` ⇒ Nexus-specific trigger, not bare Pi.

### B. Capture Nexus RPC wire log (one repro)

```bash
export NEXUS_PI_RPC_RECORD_DIR=/tmp/nexus-pi-rpc-$(date +%s)
# Rebuild & run Nexus, send one prompt, wait for stall or agent_end
ls -la "$NEXUS_PI_RPC_RECORD_DIR"   # stdin.jsonl stdout.jsonl
```

Diff stdin/stdout ordering and idle gaps against a harness run in `/tmp/pi-rpc-harness-record`.

### C. Session file vs RPC

```bash
SESSION_JSONL="$(ls -t ~/.pi/agent/sessions/--Users-ck-source-repos-nexus--/*.jsonl | head -1)"
wc -l "$SESSION_JSONL"; stat -f "%Sm" -t "%H:%M:%S" "$SESSION_JSONL"
log show --last 5m --predicate 'subsystem == "com.chundla.nexus" AND category == "SessionRuntime"'
```

- jsonl frozen + no `piAgentEnd` ⇒ Pi agent loop wedged **after** persisting tool rows to disk.
- jsonl growing + no `piAgentEnd` ⇒ still running (slow) or streaming without lifecycle events.

### D. Module integration (no UI)

```bash
swift test --package-path Modules --filter PiRPCPostToolStallDifferentialTests
```

Uses mock transport; asserts Nexus startup RPC sequence does not omit events the harness relies on.

## Phase 2 — Reproduce checklist

- [ ] Stall matches user report: prompt accepted, ≥3 tool results, ≥120s no `agent_end`
- [ ] Reproduces on **clean** Nexus build with logging commit
- [ ] Harness **baseline** completes with `agent_end` on same machine same day

## Phase 3 — Ranked falsifiable hypotheses

| # | Hypothesis | If true, then… |
|---|------------|----------------|
| 1 | **Provider/xAI stall** after parallel tools (model/provider), independent of host | Harness and Nexus-env harness both stall; jsonl frozen; same model id |
| 2 | **Nexus merged shell env** (`LocalShellEnvironmentResolver`) changes API keys, `PATH`, or proxy vs interactive shell | `nexus-shell-env` mode stalls more than `baseline`; diff `env` snapshots |
| 3 | **Stdout backpressure**: Pi blocks on full pipe because Nexus spends too long per line (persist + `getSessionScreen` on every `notifyChange`) | Stall correlates with burst of `message_update`; disabling/throttling post-observer persist reduces stall; `lsof` shows pipe buffer growth |
| 4 | **Extra RPC chatter** (startup `get_commands` / `get_available_models`, post-prompt `get_commands`, auto `get_session_stats`) tickles Pi bug | Minimal harness (prompt-only) always OK; full Nexus stdin trace shows unique commands before stall |
| 5 | **`--session` / restored linkage** resumes bad state | Fresh session (no linkage) OK; resume-only fails; transport args in `piProcessStarted` log |

Test **#2 and #4** first (cheap). **#3** needs RPC record + persist throttle experiment. **#1** only if differentials converge.

## Phase 4 — Instrumentation tags

- OSLog: `com.chundla.nexus` / `SessionRuntime` (already)
- RPC record: `NEXUS_PI_RPC_RECORD_DIR`
- Debug probes: prefix `[DEBUG-pi-stall]` (remove before merge)

## Phase 5 — Fix bar

- Regression at correct seam: `PiRPCSessionRuntime` and/or persist-on-observer policy, with mock transport replaying captured `stdout.jsonl` from a stall.
- Re-run `./scripts/diagnose-pi-rpc-nexus-vs-baseline.sh` and one manual Nexus prompt.

## Phase 6 — If root cause is #3

Architectural follow-up: decouple stdout read loop from SQLite persist (coalesce persists, async writer, or pre-observer only for deltas). Hand to `/improve-codebase-architecture` with trace showing persist duration vs inter-line RPC latency.