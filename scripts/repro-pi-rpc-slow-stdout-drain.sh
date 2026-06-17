#!/usr/bin/env bash
# Experiment #1 (backpressure): same as repro-pi-rpc-nexus-like-prompt.sh but sleeps after each stdout line
# before readline returns — simulates a slow consumer like Nexus (persist + observers per RPC line).
#
# Run from repo root:
#   ./scripts/repro-pi-rpc-slow-stdout-drain.sh
#   STDOUT_DRAIN_DELAY_SEC=0.05 ./scripts/repro-pi-rpc-slow-stdout-drain.sh
#
# Compare to fast drain:
#   ./scripts/repro-pi-rpc-nexus-like-prompt.sh
#
# Exit 4 = post-tool stall (like Nexus); 0 = agent_end.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PI="${PI:-$(command -v pi)}"
CWD="${CWD:-$ROOT}"
USER_MESSAGE="${USER_MESSAGE:-lets perform a code review on nexus}"
MODEL_PROVIDER="${MODEL_PROVIDER:-xai-auth}"
MODEL_ID="${MODEL_ID:-grok-composer-2.5-fast}"
POST_TOOL_STALL_SEC="${POST_TOOL_STALL_SEC:-120}"
OVERALL_TIMEOUT_SEC="${OVERALL_TIMEOUT_SEC:-300}"
STDOUT_DRAIN_DELAY_SEC="${STDOUT_DRAIN_DELAY_SEC:-0.05}"

export PATH="${PATH:-}"

echo "slow stdout drain: ${STDOUT_DRAIN_DELAY_SEC}s per line (Nexus backpressure experiment)"
echo "prompt: ${USER_MESSAGE}"
echo ""

python3 - "$PI" "$CWD" "$USER_MESSAGE" "$MODEL_PROVIDER" "$MODEL_ID" "$POST_TOOL_STALL_SEC" "$OVERALL_TIMEOUT_SEC" "$STDOUT_DRAIN_DELAY_SEC" <<'PY'
import json, os, select, subprocess, sys, time
from datetime import datetime, timezone

pi, cwd, user_message, model_provider, model_id, post_tool_stall_sec, overall_timeout_sec, drain_delay_sec = sys.argv[1:9]
post_tool_stall_sec = int(post_tool_stall_sec)
overall_timeout_sec = int(overall_timeout_sec)
drain_delay = float(drain_delay_sec)

startup_state_id = "nexus-pi-startup-state"
startup_commands_id = "nexus-pi-startup-commands"
startup_models_id = "nexus-pi-startup-available-models"
set_model_id = "nexus-pi-set-model-repro"
prompt_id = "nexus-pi-prompt-repro"

def ts():
    return datetime.now(timezone.utc).strftime("%H:%M:%S")

def jline(obj):
    return json.dumps(obj, separators=(",", ":")) + "\n"

def summarize_event(obj):
    t = obj.get("type")
    if t == "response":
        return f"response command={obj.get('command')} success={obj.get('success')} id={obj.get('id')}"
    if t == "message_update":
        ev = obj.get("event", {})
        return f"message_update {ev.get('type')}"
    if t == "message":
        role = (obj.get("message") or {}).get("role")
        stop = (obj.get("message") or {}).get("stopReason")
        extra = f" stop={stop}" if stop else ""
        return f"message role={role}{extra}"
    return f"type={t}"

proc = subprocess.Popen(
    [pi, "--mode", "rpc"],
    cwd=cwd,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env=os.environ.copy(),
)

def send(obj):
    line = jline(obj)
    proc.stdin.write(line)
    proc.stdin.flush()
    print(f"[{ts()}] >> {obj.get('type')} id={obj.get('id','')}", flush=True)

responses = {}
event_types = []
last_line_at = time.monotonic()
start = last_line_at
saw_tool_results = 0
saw_agent_end = False
saw_prompt_accept = None
last_assistant_stop = None
stall_reported = False
total_drain_sleep = 0.0

send({"id": startup_state_id, "type": "get_state"})
deadline = start + 15
while startup_state_id not in responses and time.monotonic() < deadline:
    if proc.poll() is not None:
        print(f"[{ts()}] Pi exited early code={proc.returncode}", flush=True)
        break
    r, _, _ = select.select([proc.stdout], [], [], 0.2)
    if not r:
        continue
    line = proc.stdout.readline()
    if not line:
        continue
    if drain_delay > 0:
        time.sleep(drain_delay)
        total_drain_sleep += drain_delay
    last_line_at = time.monotonic()
    obj = json.loads(line)
    print(f"[{ts()}] << {summarize_event(obj)}", flush=True)
    if obj.get("type") == "response" and obj.get("id") == startup_state_id:
        responses[startup_state_id] = obj

if responses.get(startup_state_id, {}).get("success") is not True:
    print(f"[{ts()}] FAIL startup get_state: {responses.get(startup_state_id)}", flush=True)
    proc.kill()
    sys.exit(2)

send({"id": startup_commands_id, "type": "get_commands"})
send({"id": startup_models_id, "type": "get_available_models"})
if model_provider and model_id:
    send({
        "id": set_model_id,
        "type": "set_model",
        "provider": model_provider,
        "modelId": model_id,
    })
    time.sleep(0.5)
    while set_model_id not in responses and time.monotonic() < start + 30:
        r, _, _ = select.select([proc.stdout], [], [], 0.2)
        if not r:
            continue
        line = proc.stdout.readline()
        if not line:
            continue
        if drain_delay > 0:
            time.sleep(drain_delay)
            total_drain_sleep += drain_delay
        last_line_at = time.monotonic()
        obj = json.loads(line)
        print(f"[{ts()}] << {summarize_event(obj)}", flush=True)
        if obj.get("type") == "response":
            rid = obj.get("id")
            if rid:
                responses[rid] = obj
            if obj.get("command") == "set_model" and obj.get("id") == set_model_id:
                break

send({"id": prompt_id, "type": "prompt", "message": user_message})

overall_deadline = start + overall_timeout_sec
while time.monotonic() < overall_deadline:
    if proc.poll() is not None:
        print(f"[{ts()}] Pi exited code={proc.returncode}", flush=True)
        break
    timeout = min(1.0, overall_deadline - time.monotonic())
    r, _, _ = select.select([proc.stdout], [], [], max(0.05, timeout))
    now = time.monotonic()
    if not r:
        idle = now - last_line_at
        if saw_tool_results >= 3 and not saw_agent_end and idle >= post_tool_stall_sec and not stall_reported:
            stall_reported = True
            print(
                f"[{ts()}] STALL: no stdout for {idle:.0f}s after {saw_tool_results} toolResult(s); "
                f"agent_end={saw_agent_end}",
                flush=True,
            )
        continue
    line = proc.stdout.readline()
    if not line:
        continue
    if drain_delay > 0:
        time.sleep(drain_delay)
        total_drain_sleep += drain_delay
    last_line_at = now
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        print(f"[{ts()}] << (non-json) {line[:120]!r}", flush=True)
        continue
    print(f"[{ts()}] << {summarize_event(obj)}", flush=True)

    if obj.get("type") == "response":
        rid = obj.get("id")
        if rid == prompt_id:
            saw_prompt_accept = obj.get("success")
        if rid:
            responses[rid] = obj
        if obj.get("command") == "prompt" and obj.get("id") == prompt_id:
            if obj.get("success") is not True:
                proc.kill()
                sys.exit(3)

    top_type = obj.get("type")
    if top_type == "message_update":
        et = (obj.get("event") or {}).get("type")
        if et:
            event_types.append(et)
    elif top_type == "message":
        msg = obj.get("message") or {}
        role = msg.get("role")
        if role == "toolResult":
            saw_tool_results += 1
        if role == "assistant":
            last_assistant_stop = msg.get("stopReason")
        event_types.append(f"message:{role}")
    elif top_type in (
        "agent_start", "agent_end", "turn_end", "message_end",
        "tool_execution_start", "tool_execution_update", "tool_execution_end",
        "thinking_level_changed", "extension_error",
    ):
        event_types.append(top_type)
        if top_type == "agent_end":
            saw_agent_end = True
            print(f"[{ts()}] DONE agent_end after {now - start:.1f}s", flush=True)
            break

print(
    f"[{ts()}] SUMMARY drain_delay={drain_delay}s total_drain_sleep={total_drain_sleep:.1f}s "
    f"elapsed={time.monotonic()-start:.1f}s toolResults={saw_tool_results} agent_end={saw_agent_end}",
    flush=True,
)
print(f"[{ts()}] event_type_counts={ {k: event_types.count(k) for k in sorted(set(event_types))} }", flush=True)

if stall_reported and not saw_agent_end:
    proc.kill()
    sys.exit(4)
if not saw_agent_end:
    proc.kill()
    sys.exit(5)
proc.kill()
sys.exit(0)
PY