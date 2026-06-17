#!/usr/bin/env bash
# Differential loop: same prompt, three launch envelopes. Exit 0=all pass; 1=usage; 2=baseline fail; 3=env fail; 4=any stall.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$ROOT/scripts/repro-pi-rpc-nexus-like-prompt.sh"
USER_MESSAGE="${USER_MESSAGE:-lets perform a code review on nexus}"
POST_TOOL_STALL_SEC="${POST_TOOL_STALL_SEC:-90}"
OVERALL_TIMEOUT_SEC="${OVERALL_TIMEOUT_SEC:-240}"

if [[ ! -x "$HARNESS" ]]; then
  chmod +x "$HARNESS"
fi

run_mode() {
  local label="$1"
  shift
  local log="/tmp/pi-rpc-diff-${label}-$$.log"
  echo "=== MODE: $label ===" | tee "$log"
  if "$@" 2>&1 | tee -a "$log"; then
    echo "RESULT $label: PASS (exit 0)" | tee -a "$log"
    return 0
  else
    local ec=$?
    echo "RESULT $label: FAIL (exit $ec)" | tee -a "$log"
    return "$ec"
  fi
}

# Baseline: harness default (minimal Pi RPC sequence inside python, same as early repro)
baseline() {
  env -i \
    HOME="${HOME}" \
    PATH="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" \
    USER="${USER:-$(id -un)}" \
    LOGNAME="${LOGNAME:-$(id -un)}" \
    SHELL="${SHELL:-/bin/zsh}" \
    CWD="$ROOT" \
    USER_MESSAGE="$USER_MESSAGE" \
    POST_TOOL_STALL_SEC="$POST_TOOL_STALL_SEC" \
    OVERALL_TIMEOUT_SEC="$OVERALL_TIMEOUT_SEC" \
    "$HARNESS"
}

# Approximate Nexus LocalShellEnvironmentResolver: login shell exports merged into harness env
nexus_shell_env() {
  local shell_env_file
  shell_env_file="$(mktemp)"
  # Same idea as LocalShellCommandBuilder + /usr/bin/env -0
  "${SHELL:-/bin/zsh}" -lic '/usr/bin/env -0' 2>/dev/null >"$shell_env_file" || true
  if [[ ! -s "$shell_env_file" ]]; then
    /bin/zsh -lic '/usr/bin/env -0' 2>/dev/null >"$shell_env_file" || true
  fi
  export CWD="$ROOT" USER_MESSAGE="$USER_MESSAGE"
  export POST_TOOL_STALL_SEC="$POST_TOOL_STALL_SEC" OVERALL_TIMEOUT_SEC="$OVERALL_TIMEOUT_SEC"
  python3 - "$shell_env_file" "$HARNESS" <<'PY'
import os, subprocess, sys
env_path, harness = sys.argv[1], sys.argv[2]
env = os.environ.copy()
with open(env_path, "rb") as f:
    for entry in f.read().split(b"\0"):
        if not entry or b"=" not in entry:
            continue
        k, _, v = entry.partition(b"=")
        try:
            env[k.decode()] = v.decode()
        except UnicodeDecodeError:
            pass
env["CWD"] = os.environ.get("CWD", "")
env["USER_MESSAGE"] = os.environ.get("USER_MESSAGE", "")
env["POST_TOOL_STALL_SEC"] = os.environ.get("POST_TOOL_STALL_SEC", "90")
env["OVERALL_TIMEOUT_SEC"] = os.environ.get("OVERALL_TIMEOUT_SEC", "240")
raise SystemExit(subprocess.call([harness], env=env))
PY
  rm -f "$shell_env_file"
}

echo "Prompt: $USER_MESSAGE"
echo "stall threshold: ${POST_TOOL_STALL_SEC}s overall: ${OVERALL_TIMEOUT_SEC}s"
echo ""

FAIL=0
run_mode baseline baseline || FAIL=1
echo ""
run_mode nexus-shell-env nexus_shell_env || FAIL=2

echo ""
echo "=== SUMMARY ==="
if [[ "$FAIL" -eq 0 ]]; then
  echo "All modes completed with agent_end. Nexus-only stall is NOT reproduced in harness — use NEXUS_PI_RPC_RECORD_DIR on live Nexus + compare stdout gaps."
  exit 0
fi
if [[ "$FAIL" -eq 1 ]]; then
  echo "Baseline harness failed — fix harness/env before blaming Nexus."
  exit 2
fi
echo "nexus-shell-env diverged from baseline — investigate env merge (hypothesis #2)."
exit 4