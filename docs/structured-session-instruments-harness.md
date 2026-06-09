# Structured Session Instruments harness (#219)

Maintainer-local workflow to reproduce the **09-06** live structured **Session** workload and export comparable SwiftUI hitch metrics for macOS and iOS **before/after** perf slices (#215–#220).

This harness does **not** run in CI and does **not** require a paired physical device in automation. Final SwiftUI traces still require Xcode Instruments (or `xctrace`) on a Mac; iOS SwiftUI templates require a **physical iPhone** (not Simulator).

## Prerequisites

- Xcode with Instruments (`xcrun xctrace list templates` shows `SwiftUI`)
- Debug build of `nexus.app` from this repo (confirm process path in the trace summary)
- Optional: local copy of umbrella baseline trace `09-06.trace` (repo root; not committed—650MB+)

Validate the export script (no trace required):

```bash
python3 scripts/test_export_structured_session_trace_metrics.py
```

## Workload (match 09-06)

Record **~5–7 minutes** of steady structured-feed interaction while the Pi stream fixture runs:

1. Let the fixture settle on the structured **Session** feed (preseeded history + live draft ticks).
2. Scroll **up** through history, then return to **follow bottom** / latest messages.
3. Leave the trace running through at least one **draft expand → finalize → next turn** cycle.
4. Avoid unrelated navigation (Workspace browse, pairing flows).

### macOS Debug `nexus.app`

1. In the **nexus** scheme, set environment variable `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile`.
2. Run **Debug** on **My Mac** (or Product → Profile with the same env var).
3. Instruments → **SwiftUI** template → Record.
4. Perform the workload above → Stop → save as e.g. `structured-feed-profile-macos.trace`.

Pre-flight (automated, no Instruments):

```bash
xcodebuild test -scheme nexus -project nexus.xcodeproj -destination 'platform=macOS' \
  -only-testing:nexusTests/NexusAppProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBurstsOnMacOS
```

See also [performance-baselines.md](./performance-baselines.md) — *Repeatable macOS structured feed trace fixture*.

### iOS device build

1. On a **physical iPhone** scheme, set `NEXUS_REMOTE_CLIENT_FIXTURE=streaming-feed-profile`.
2. Build & run Debug, open **Baseline API → Pi → Open conversation** (fixture pre-navigates when configured).
3. Instruments → **SwiftUI** on the device → Record → same scroll/stream workload → Stop.

Pre-flight:

```bash
xcodebuildmcp macos test --project-path nexus.xcodeproj --scheme nexus \
  --extra-args -only-testing:nexusTests/RemoteClientProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBursts
```

Simulator can rehearse navigation with the same env var, but **`xctrace` SwiftUI is not supported on Simulator** for this app—use a device for exported hitch tables.

## Export hitch metrics (`hitches` schemas)

From a saved `.trace`:

```bash
python3 scripts/export_structured_session_trace_metrics.py \
  --input /path/to/your.trace \
  --output /tmp/structured-session-metrics.json
```

The script exports per-run:

| Field | Source schema | Use |
| --- | --- | --- |
| `red_marked_count`, `worst_red_marked_ms` | `hitches-updates` (Red + containment level 1) | Instruments-marked hitch events |
| `frame_lifetime_over_16_67ms_count`, `frame_lifetime_over_33ms_count`, `worst_frame_lifetime_ms` | `hitches-frame-lifetimes` | Frame budget regressions |
| `update_groups_worst_ms`, `top_update_group_descriptions` | `swiftui-update-groups` | Expensive SwiftUI update clusters |

Manual `xctrace` exports (same tables Instruments UI uses):

```bash
xcrun xctrace export --input your.trace --toc
xcrun xctrace export --input your.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches-updates"]' \
  --output /tmp/hitches-updates-run1.xml
xcrun xctrace export --input your.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches-frame-lifetimes"]' \
  --output /tmp/hitches-frame-lifetimes-run1.xml
xcrun xctrace export --input your.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="swiftui-update-groups"]' \
  --output /tmp/swiftui-update-groups-run1.xml
```

In Instruments UI, open **Hitches** / **SwiftUI** tracks and note **Potentially expensive app update(s)** strings for the same session window.

## Umbrella baseline (`09-06.trace`, pre–#215–#218 fixes)

Captured 2026-06-09; parent context: issue **#214**. Re-export after pulling a local `09-06.trace`:

```bash
python3 scripts/export_structured_session_trace_metrics.py \
  --input 09-06.trace \
  --output docs/baselines/09-06-structured-session-metrics.json
```

Committed snapshot (from local `09-06.trace` via `export_structured_session_trace_metrics.py`):

- [baselines/09-06-structured-session-metrics.json](./baselines/09-06-structured-session-metrics.json)

CLI `red_marked_count` counts Instruments **Red** hitch markers in `hitches-updates` (often 1 per severe cluster). The **#214** UI counts (39 macOS / 62 iOS) come from the SwiftUI **Hitches** track—use both when comparing.

**Qualitative notes from #214 triage** (Instruments UI; use when comparing traces visually):

| Run | Platform | Duration | Hitch notes (UI) |
| --- | --- | --- | --- |
| 1 | macOS | ~6.3 min | 39 hitches; worst **166.7 ms** (~4:13); typesetter / `ResolvedStyledText` hot stacks |
| 2 | iOS | ~7 min | 62 hitches; clusters 16–87 ms; **109 offscreen passes** on one hitch (~3:59) |

Post–#215–#217 (and #218 on iOS), record a **new** trace with the same harness and compare JSON + UI hitch counts against this baseline. Comment results on **#214**.

### macOS text layout slice (#220)

Code-side mitigations (automated guardrails + macOS `ContentView`):

- `structuredSessionDetailTextPreview` still bounds row `detailText` at build time (12 lines / 4k chars).
- Finalized assistant markdown uses `structuredSessionFeedAssistantMarkdownDisplayPolicy` (same thresholds as streaming collapse) with a fixed **200 pt** viewport when long.
- System-card markdown `detailText` uses the same bounded viewport as command detail previews.
- Presentation tests: `structuredSessionFeedAssistantMarkdownDisplayPolicyBoundsLongFinalizedResponses` plus existing collapse/detail-preview tests.

After rebuilding macOS Debug from HEAD, re-profile with `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile` and export metrics; compare worst hitch / hitch count to the 09-06 baseline above.

## Related

- Umbrella: GitHub issue **#214**
- Automated service baselines: [performance-baselines.md](./performance-baselines.md)
- iOS offscreen mitigations ADR: [adr/0036-structured-session-feed-ios-gpu-offscreen-mitigations.md](./adr/0036-structured-session-feed-ios-gpu-offscreen-mitigations.md)