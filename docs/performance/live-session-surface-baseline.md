# Live Session surface baseline

Use the benchmark harness in `nexus/NexusBenchmarkHarness.swift` to capture repeatable Release-build baselines for the live **Session Surface** on macOS and the iPhone **Remote Client**.

## Scenarios

| Scenario | Surface | Client | Notes |
| --- | --- | --- | --- |
| `mac-terminal-busy` | terminal | macOS Nexus client | 34x118 terminal viewport, 48 looping frames, 140ms step |
| `mac-structured-streaming` | structured activity feed | macOS Nexus client | 18 looping frames, growing structured activity list, 350ms step |
| `iphone-terminal-busy` | terminal | iPhone Remote Client | Reuses the busy terminal fixture inside `RemoteSessionScreenView` |
| `iphone-structured-streaming` | structured activity feed | iPhone Remote Client | Reuses the structured fixture inside `RemoteSessionScreenView` |

Each scenario is selected with `NEXUS_BENCHMARK_SCENARIO` and requires no manual interaction after launch. Let the scenario loop and capture the steady-state window.

## One-command capture scaffold

```bash
./scripts/perf/capture_live_session_surface_baseline.sh
```

The script:
- builds Release for macOS and iOS Simulator unless `NEXUS_BENCHMARK_SKIP_BUILD=1`
- records macOS `Time Profiler` traces for both macOS scenarios
- records macOS `SwiftUI` template traces for both macOS scenarios
- exports compact Markdown summaries from the macOS `Time Profiler` traces
- boots an iPhone simulator, launches both iPhone scenarios, and saves screenshots for later comparison
- writes a per-run `README.md` with the manual follow-up steps for iPhone Instruments captures

Useful environment overrides:

```bash
NEXUS_BENCHMARK_SKIP_BUILD=1 \
NEXUS_BENCHMARK_SIMULATOR_ID=<simulator-udid> \
NEXUS_BENCHMARK_DERIVED_DATA_DIR=~/Library/Developer/Xcode/DerivedData/nexus-... \
./scripts/perf/capture_live_session_surface_baseline.sh /tmp/nexus-baseline
```

## Exact Release capture recipe

### macOS Nexus client

Time Profiler:

```bash
xcrun xctrace record \
  --template 'Time Profiler' \
  --time-limit 20s \
  --window 10s \
  --env NEXUS_BENCHMARK_SCENARIO=mac-terminal-busy \
  --output /tmp/mac-terminal-busy.time-profiler.trace \
  --launch -- ~/Library/Developer/Xcode/DerivedData/<derived>/Build/Products/Release/nexus.app/Contents/MacOS/nexus
```

SwiftUI template:

```bash
xcrun xctrace record \
  --template 'SwiftUI' \
  --time-limit 20s \
  --window 10s \
  --env NEXUS_BENCHMARK_SCENARIO=mac-structured-streaming \
  --output /tmp/mac-structured-streaming.swiftui.trace \
  --launch -- ~/Library/Developer/Xcode/DerivedData/<derived>/Build/Products/Release/nexus.app/Contents/MacOS/nexus
```

Export a compact summary from a Time Profiler trace:

```bash
./scripts/perf/summarize_time_profiler_trace.py /tmp/mac-terminal-busy.time-profiler.trace
```

### iPhone Remote Client

1. Build the iOS Simulator Release app.
2. Install it on a booted iPhone simulator.
3. Launch one benchmark scenario:

```bash
xcrun simctl launch --terminate-running-process <simulator-udid> com.chundla.nexus \
  NEXUS_BENCHMARK_SCENARIO=iphone-terminal-busy
```

4. Capture a screenshot for the comparison artifact:

```bash
xcrun simctl io <simulator-udid> screenshot /tmp/iphone-terminal-busy.png
```

5. Open Instruments.app and attach either `Time Profiler` or `SwiftUI` to the running simulator app.
6. Let the scenario loop for 20s and keep the last 10s steady-state window.
7. Repeat for `iphone-structured-streaming`.

## Known limitation on this machine

`xcrun xctrace record` is reliable for the macOS Release app here, but Xcode 17F42 on this machine does not consistently finalize CLI traces when the target is an iOS Simulator process. Use Instruments.app for the iPhone Remote Client traces until that tooling issue is resolved.

## Comparison artifact

Keep the compact artifact small and durable:
- the per-run Markdown summaries from `scripts/perf/summarize_time_profiler_trace.py`
- the iPhone benchmark screenshots saved by the capture script
- one short metrics/call-tree note in the issue body or an issue comment

The checked-in baseline note for this work lives at `docs/performance/live-session-surface-baseline-2026-05-31.md`.
