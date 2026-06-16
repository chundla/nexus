#!/usr/bin/env bash
# Minimal Pi RPC: get_state + prompt only (no Nexus model switch).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export USER_MESSAGE="${USER_MESSAGE:-lets perform a code review on nexus}"
export MODEL_PROVIDER=""
export MODEL_ID=""
export POST_TOOL_STALL_SEC="${POST_TOOL_STALL_SEC:-90}"
export OVERALL_TIMEOUT_SEC="${OVERALL_TIMEOUT_SEC:-150}"
export CWD="${CWD:-$ROOT}"
exec "$(dirname "$0")/repro-pi-rpc-nexus-like-prompt.sh"