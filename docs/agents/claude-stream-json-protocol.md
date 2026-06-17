# Claude Code CLI `stream-json` protocol spike and event mapping spec

Spike for issue #249, implementing ADR 0038 (`docs/adr/0038-claude-structured-sessions-use-cli-stream-json.md`). Captured by running the real `claude` CLI in print mode with bidirectional `stream-json` against a scratch git workspace. Later structured-Claude slices (#250-#255) should cite this doc rather than re-deriving the protocol.

**Validated against:** `claude --version` → `2.1.179 (Claude Code)`. No older version was tested; treat `2.1.179` as the only confirmed-compatible version until a follow-up spike checks compatibility range (acceptance criterion: "TBD after spike" for a hard minimum).

## 1. Invocation

```
claude -p \
  --input-format stream-json --output-format stream-json \
  --include-partial-messages --verbose \
  --permission-mode default \
  --add-dir <workspace-path> \
  [--session-id <uuid> | --resume <uuid>] \
  [--settings <hooks-json>]
```

Findings on flags:

- `--output-format stream-json` **requires** `--verbose` (the CLI hard-errors otherwise: `Error: When using --print, --output-format=stream-json requires --verbose`). Nexus's launch command must always pass both together.
- `--input-format stream-json` expects newline-delimited JSON on stdin. A user turn is sent as:
  ```json
  {"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}
  ```
- `--no-session-persistence` disables `--resume` entirely (`No conversation found with session ID: ...`). Nexus must **not** pass `--no-session-persistence` for any Session it intends to relaunch/resume; only use it for ephemeral Provider Health probes (§5).
- `cwd` is reported in `system/init` as the realpath (e.g. `/private/tmp/...` for a `/tmp/...` workspace on macOS) — don't assume byte-identity with the configured Workspace path when correlating.

## 2. Observed `stream-json` event catalog

Top-level line `type` values seen, in the order they appear for a simple turn:

| `type` | `subtype` / `event.type` | When | Notes |
|---|---|---|---|
| `system` | `init` | Once, on first message of a session | Carries `session_id`, `cwd`, `model`, `permissionMode`, `tools`, `slash_commands`, `claude_code_version` |
| `system` | `status` (`status: "requesting"`) | Before each model request | Lightweight "thinking about it" signal |
| `stream_event` | `event.type: message_start` | Start of an assistant message | Contains initial (empty) `usage` |
| `stream_event` | `event.type: content_block_start` | Start of a content block | `content_block.type` is `text`, `thinking`, or `tool_use` |
| `stream_event` | `event.type: content_block_delta` | Per-token/per-chunk streaming | `delta.type` is `text_delta`, `thinking_delta`/`signature_delta`, or `input_json_delta` (for `tool_use` args) |
| `stream_event` | `event.type: content_block_stop` | End of a content block | |
| `stream_event` | `event.type: message_delta` | End of an assistant message | Carries `stop_reason`, final `usage` |
| `stream_event` | `event.type: message_stop` | After `message_delta` | No payload beyond the type |
| `assistant` | — | Coalesced assistant message (same content as the stream_event sequence, fully assembled) | `message.content` is an array of blocks: `text`, `thinking`, `tool_use` |
| `user` | — | Synthetic "user" line carrying a `tool_result` | Always wraps a `tool_use_id`; this is how tool output (success **and** denial) re-enters the transcript, not a real human turn |
| `rate_limit_event` | — | Periodically | `rate_limit_info.status`, `resetsAt`, `rateLimitType` |
| `result` | `success` / `error_during_execution` / other | Once, end of the whole `-p` invocation (all turns) | Final rollup: `result` (text), `num_turns`, `total_cost_usd`, `usage`, `permission_denials[]`, `stop_reason`, `session_id` |

Sample payloads (trimmed, no secrets in this workspace):

**`system/init`**
```json
{"type":"system","subtype":"init","cwd":"/private/tmp/nexus-claude-spike","session_id":"e7ff7d3e-fb81-45c3-adf6-6a08cf3243ef","model":"claude-sonnet-4-6","permissionMode":"default","claude_code_version":"2.1.179", "...": "tools[], slash_commands[], agents[], skills[] elided"}
```

**`stream_event` text delta**
```json
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"p"}},"session_id":"...","uuid":"..."}
```

**`assistant` with `tool_use`**
```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01VBshTLzFEejNJK6YTrfpvf","name":"Read","input":{"file_path":"/private/tmp/nexus-claude-spike/README.md"}}]},"session_id":"..."}
```

**`user` carrying `tool_result`**
```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01VBshTLzFEejNJK6YTrfpvf","type":"tool_result","content":"1\t# spike workspace\n2\t"}]},"session_id":"...","tool_use_result":{"type":"text","file":{"filePath":"...","content":"...","numLines":2}}}
```

**`result`**
```json
{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"pong","stop_reason":"end_turn","session_id":"...","total_cost_usd":0.1506,"permission_denials":[]}
```

## 3. Mapping to `SessionActivityItem` / `SessionProviderEvent`

Convention check against existing providers (Codex in `CodexAppServerRuntime.swift`, pi in `PiRPCSessionRuntime.swift`): `.command` = tool/sub-process announcements, `.message` = assistant text (and tool output deltas prefixed with a tool label), `.approvalRequest`/`.approvalDecision` = the approval lifecycle, `.status` = transient progress chrome, `.error` = failures. Claude should follow the same shape rather than inventing new `Kind` values.

| stream-json event | `SessionActivityItem.Kind` | `SessionProviderEvent.Family` | Notes |
|---|---|---|---|
| `system/init` | `.status` (one-time "session started") | `.agent` | Also the source of session id metadata (§4) |
| `system/status` (`requesting`) | `.status` | `.agent` | Matches Codex's "Codex shared Session stream connected" style status row |
| `stream_event` `message_start`/`content_block_start`/`content_block_delta`/`content_block_stop`/`message_delta`/`message_stop` | not surfaced 1:1 as activity items | `.message` | Used to assemble `StructuredSessionProviderFacts.liveAssistantDraftText`, same role as pi's `message_update`/`text_delta` handling — one item per delta would spam the feed |
| `assistant` content block `text` (final) | `.message` | `.message` | Final assistant text, analogous to Codex's `"Codex: \(text)"` |
| `assistant` content block `thinking` | `.message` (or routed to the Agent Turn "Reasoning" split per ADR 0037) | `.message` | Maps to the reasoning row, not the final-answer row |
| `assistant` content block `tool_use` | `.command` | `.toolExecution` | Tool name + key args, same as Codex's `codexToolAnnouncement` |
| `user` (`tool_result`, success) | `.message` (tool-output delta, label-prefixed) | `.toolExecution` | Matches Codex's `"\(toolLabel): \(outputDelta)"` |
| `user` (`tool_result`, `is_error: true`, permission-denied text) | `.error` or `.approvalDecision` (see §6) | `.toolExecution` | The auto-deny case (§6) surfaces here, not as a separate approval-prompt event |
| `rate_limit_event` | not surfaced as an activity item | `.unknown` | Useful for Provider Health / capacity diagnostics, not user-facing feed content |
| `result` (`success`) | `.completion` | `.turn` | Turn/session completion; `num_turns`, `total_cost_usd`, `usage` feed `StructuredSessionProviderFacts` |
| `result` (non-success subtype) | `.error` | `.turn` | |

## 4. Session id source of truth

- The Claude session id is the `session_id` field present on **every** stream-json line, first observed on `system/init`.
- Nexus should **pre-assign** the id rather than capture it after the fact: passing `--session-id <uuid>` (a client-generated UUID) makes the CLI adopt that exact id as `session_id` in `system/init` and in the persisted transcript. Confirmed: launching with `--session-id aa80e0d8-...` produced `system/init session_id: aa80e0d8-...`.
- Store that UUID as the **Session Record** adapter metadata (per ADR 0038, 1:1 mapping). Relaunch/resume uses `--resume <same-uuid>`; the session id is stable across resume (no `--fork-session`). Confirmed end-to-end: a turn that asked Claude to remember a word, followed by a fresh process launched with `--resume <uuid>`, recalled the word correctly and reported the same `session_id`.
- `--resume` only works if the original process was **not** launched with `--no-session-persistence`. Reserve `--no-session-persistence` for the Provider Health probe (§5), never for a real Session.
- `--fork-session` (untested here) is the documented escape hatch for "resume into a new id" — relevant if Nexus ever needs branch-without-mutating-original semantics; not needed for the 1:1 mapping case.

## 5. Provider Health capability probe

**Local probe (defined here):**

1. Resolve executable + version the same way other providers do (ADR 0015): run `claude --version`. Observed: ~70ms, stdout `2.1.179 (Claude Code)`, exit 0.
2. `stream-json` readiness probe: spawn `claude -p --input-format stream-json --output-format stream-json --verbose --permission-mode default --add-dir <workspace> --no-session-persistence`, write one trivial user-message line to stdin, and wait for a `system/init` line on stdout.
   - **Success:** a parseable `system/init` line with non-empty `session_id` and matching `cwd` arrives within the timeout. Observed latency in this spike: ~0.4s from writing the input line to the `init` line appearing — well before any model call completes, so the probe does not need to wait for (or pay for) a full turn.
   - **Failure:** non-zero exit before `init`, malformed/missing `init` line, or timeout exceeded (recommend ≥5s timeout given the ~0.4s observed baseline plus headroom for cold start / disk-heavy `cwd`).
   - After observing `init` (or timing out), kill the child process — do not wait for `result`.
   - **Caveat:** because the probe must send a real user message to provoke any output at all (a bare process with stdin held open and zero messages produces **no** output, confirmed by spike), the in-flight request may already be dispatched to the model API by the time the probe kills the process. This differs from a free liveness check; keep the probe message minimal and treat the (likely negligible) cost as accepted overhead. Flag for #251 to decide if this is acceptable or if a cheaper signal should be found.

**Remote probe (sketch only — full spec is #251):** same two checks (`claude --version`, stream-json readiness) executed over the SSH stdio bridge to the Host per ADR 0031, inside the tmux-durable runner rather than a one-off process. Latency budget should account for SSH round-trip in addition to the ~0.4s local baseline.

## 6. Approval Request lifecycle mapping — key spike finding

**The bare CLI invocation in ADR 0038 (`-p --input-format stream-json --output-format stream-json`, no extra control channel) does *not* surface an interactive, app-answerable permission prompt.** This is the most important and most surprising result of this spike, and it's a load-bearing open question for ADR 0038's "permission prompts map to shared Approval Requests" consequence.

What was actually observed when a `default`-permission-mode tool call needs approval (e.g. `Write`, `Edit`) and no approval mechanism is wired up:

- The tool call is **auto-denied synchronously**. The CLI emits a synthetic `user`/`tool_result` line:
  ```json
  {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Claude requested permissions to write to /path/to/file, but you haven't granted it yet.","is_error":true,"tool_use_id":"toolu_..."}]}}
  ```
- The final `result` line lists it under `permission_denials: [{"tool_name":"Write","tool_use_id":"...","tool_input":{...}}]`.
- Claude then continues the conversation, typically asking the (synthetic) user to grant permission — there is no separate "pending approval" event to hold open.
- No `control_request`/`can_use_tool` message appears on stdout in this mode. (That control-protocol shape exists inside the CLI binary, but is wired to the Claude Agent SDK / remote-control bridge path, not the bare `-p` stream-json channel — and ADR 0038 explicitly rejects the Agent SDK.)

**Viable headless mechanism found: `PreToolUse` hooks.** Configuring a `PreToolUse` hook via `--settings` (or project `settings.json`) intercepts the tool call *before* the auto-deny path and lets an external process decide synchronously:

```json
{"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"/path/to/nexus-permission-bridge"}]}]}}
```

The hook process receives this on stdin:
```json
{"session_id":"...","cwd":"/private/tmp/nexus-claude-spike","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"...","content":"..."},"tool_use_id":"toolu_..."}
```

and must print this on stdout to decide:
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"..."}}
```

Confirmed end-to-end both directions in this spike: `permissionDecision: "allow"` let a `Write` tool call create the file; `permissionDecision: "deny"` blocked it and the `permissionDecisionReason` string ("nexus-spike-auto-deny") became the `tool_result.content` the model saw.

**Mapping for #250-#252:** the `PreToolUse` hook invocation is the actual Approval Request entry point, not a stream-json event:

- Hook invoked → register `SessionApprovalRequest(state: .pending)` + `SessionActivityItem(kind: .approvalRequest, ...)`, same as Codex's `registerApprovalRequest`.
- App decision → the hook process (which Nexus controls) must block waiting for that decision (e.g. round-trip to the Background Service over local IPC) and then print the `permissionDecision` JSON to resolve the CLI's blocked tool call — this is the inverse of Codex's "send JSON-RPC response" but the same lifecycle shape: `.approvalDecision` activity item + `SessionApprovalRequest` state transition to `.approved`/`.denied`.
- The synthetic auto-deny path (§ above) becomes dead code once a `PreToolUse` hook is always configured for Claude Sessions — but Nexus should still handle a stray auto-deny `tool_result` defensively (e.g. hook process crashed) by surfacing it as `.error`, not silently dropping it.

**Open follow-ups (do not block #249, but #250/#252 need answers):**
- Confirm the default/maximum `timeout` (seconds) Claude Code allows a `PreToolUse` hook to block before treating it as denied/erroring — strings in the binary show a per-hook `timeout` setting exists, but the spike didn't conclusively pin a default value across all hook types.
- Decide the hook→Background-Service IPC shape (likely a tiny long-lived helper binary that Nexus spawns as the hook command, talking back to the existing local IPC, blocking until the user answers).
- Confirm whether `EnterPlanMode`/`AskUserQuestion` (both present in `system/init` `tools[]`) need their own hook matchers beyond `PreToolUse`, since they're plan-mode/clarification flows rather than file/command permission flows.

## 7. Summary for #250-#255

- Launch with `-p --input-format stream-json --output-format stream-json --verbose --permission-mode default --add-dir <workspace> --session-id <pre-assigned-uuid>`, plus a `--settings` `PreToolUse` hook pointing at a Nexus-owned bridge process.
- Never pass `--no-session-persistence` for a real Session; reserve it for the Provider Health probe.
- Resume with `--resume <same-uuid>`.
- Stream parsing must coalesce `stream_event` deltas into the eventual `assistant` line rather than emitting one `SessionActivityItem` per token.
- Approval Requests are driven by the `PreToolUse` hook contract, not by any event on the stream-json stdout/stdin channel itself.
