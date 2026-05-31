#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA_DIR="${NEXUS_BENCHMARK_DERIVED_DATA_DIR:-$HOME/Library/Developer/Xcode/DerivedData/nexus-cngzxhfiojdlwcaqablaukuovcpr}"
MAC_APP="$DERIVED_DATA_DIR/Build/Products/Release/nexus.app/Contents/MacOS/nexus"
IOS_APP="$DERIVED_DATA_DIR/Build/Products/Release-iphonesimulator/nexus.app"
OUTPUT_DIR="${1:-$ROOT_DIR/artifacts/live-session-surface-baseline/$(date +%Y-%m-%d-%H%M%S)}"
SKIP_BUILD="${NEXUS_BENCHMARK_SKIP_BUILD:-0}"
SIMULATOR_ID="${NEXUS_BENCHMARK_SIMULATOR_ID:-}"
TIME_LIMIT="${NEXUS_BENCHMARK_TIME_LIMIT:-20s}"
WINDOW="${NEXUS_BENCHMARK_WINDOW:-10s}"
SCREENSHOT_DELAY_SECONDS="${NEXUS_BENCHMARK_SCREENSHOT_DELAY_SECONDS:-3}"
BUNDLE_ID="com.chundla.nexus"

mkdir -p "$OUTPUT_DIR"/{macos,iphone}

resolve_simulator_id() {
  if [[ -n "$SIMULATOR_ID" ]]; then
    printf '%s\n' "$SIMULATOR_ID"
    return
  fi

  local booted
  booted="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/ { print $(NF-1); exit }')"
  if [[ -n "$booted" ]]; then
    printf '%s\n' "$booted"
    return
  fi

  local available
  available="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Simulator/ { print $(NF-1); exit }')"
  if [[ -z "$available" ]]; then
    available="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $(NF-1); exit }')"
  fi
  if [[ -z "$available" ]]; then
    echo 'Could not resolve an available iPhone simulator.' >&2
    exit 1
  fi

  printf '%s\n' "$available"
}

build_release_apps() {
  xcodebuild build -scheme nexus -configuration Release -destination 'platform=macOS'
  xcodebuild build -scheme nexus -configuration Release -destination "platform=iOS Simulator,id=$SIMULATOR_ID"
}

capture_macos_trace() {
  local scenario="$1"
  local template="$2"
  local basename="$3"
  local trace_path="$OUTPUT_DIR/macos/$basename.trace"
  local log_path="$OUTPUT_DIR/macos/$basename.log"

  xcrun xctrace record \
    --template "$template" \
    --time-limit "$TIME_LIMIT" \
    --window "$WINDOW" \
    --env "NEXUS_BENCHMARK_SCENARIO=$scenario" \
    --output "$trace_path" \
    --launch -- "$MAC_APP" \
    >"$log_path" 2>&1 || true

  if [[ "$template" == 'Time Profiler' ]]; then
    "$ROOT_DIR/scripts/perf/summarize_time_profiler_trace.py" "$trace_path" > "$OUTPUT_DIR/macos/$basename.summary.md"
  fi
}

capture_iphone_screenshot() {
  local scenario="$1"
  local png_path="$OUTPUT_DIR/iphone/$scenario.png"

  xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$BUNDLE_ID" "NEXUS_BENCHMARK_SCENARIO=$scenario" >/dev/null
  sleep "$SCREENSHOT_DELAY_SECONDS"
  xcrun simctl io "$SIMULATOR_ID" screenshot "$png_path" >/dev/null
  xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null || true
}

write_readme() {
  cat > "$OUTPUT_DIR/README.md" <<EOF
# Live Session surface baseline capture

This directory was produced by `./scripts/perf/capture_live_session_surface_baseline.sh`.

## Included artifacts
- macOS Time Profiler traces for `mac-terminal-busy` and `mac-structured-streaming`
- macOS SwiftUI template traces for the same two scenarios
- iPhone Remote Client simulator screenshots for `iphone-terminal-busy` and `iphone-structured-streaming`
- Markdown summaries exported from the macOS Time Profiler traces

## Manual follow-up for iPhone Instruments traces
At the moment, Xcode 17F42 on this machine does not reliably finalize `xcrun xctrace record` runs when the target is an iOS Simulator process. Use Instruments.app for the iPhone Remote Client captures:

1. Boot the simulator recorded in this directory and install the Release app.
2. Launch `$BUNDLE_ID` with one of:
   - `NEXUS_BENCHMARK_SCENARIO=iphone-terminal-busy`
   - `NEXUS_BENCHMARK_SCENARIO=iphone-structured-streaming`
3. Start a Time Profiler trace in Instruments.app, attach to the simulator app, let the scenario loop for 20s, and keep the last 10s steady-state window.
4. Repeat with the SwiftUI template.
5. Export the call-tree notes or screenshots beside these files so later issues can compare like-for-like captures.
EOF
}

SIMULATOR_ID="$(resolve_simulator_id)"

if [[ "$SKIP_BUILD" != '1' ]]; then
  build_release_apps
fi

if [[ ! -x "$MAC_APP" ]]; then
  echo "Missing macOS Release app: $MAC_APP" >&2
  exit 1
fi

if [[ ! -d "$IOS_APP" ]]; then
  echo "Missing iOS Simulator Release app: $IOS_APP" >&2
  exit 1
fi

capture_macos_trace 'mac-terminal-busy' 'Time Profiler' 'mac-terminal-busy.time-profiler'
capture_macos_trace 'mac-structured-streaming' 'Time Profiler' 'mac-structured-streaming.time-profiler'
capture_macos_trace 'mac-terminal-busy' 'SwiftUI' 'mac-terminal-busy.swiftui'
capture_macos_trace 'mac-structured-streaming' 'SwiftUI' 'mac-structured-streaming.swiftui'

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$IOS_APP" >/dev/null
capture_iphone_screenshot 'iphone-terminal-busy'
capture_iphone_screenshot 'iphone-structured-streaming'
write_readme

echo "Wrote live session surface baseline artifacts to: $OUTPUT_DIR"
