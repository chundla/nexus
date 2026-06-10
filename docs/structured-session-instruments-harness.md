# Structured Session Instruments harness (#219)

Maintainer-local workflow to reproduce the **09-06** live structured **Session** workload and export comparable SwiftUI hitch metrics for macOS and iOS **before/after** perf slices (#215–#220).

**Agents:** trace-gated work (**#224**, **#225**) uses the [SwiftUI trace diagnosis loop](./agents/swiftui-trace-diagnosis-loop.md) (`swiftui-trace-diagnosis` subagent), not the TDD subagent by default.

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

### Windowed analysis — required for **#224** / **#225** sign-off

Aggregate JSON above is not enough: `swiftui-update-groups` is often empty in repo export, and full-session rates mix startup with steady streaming. After every macOS post-fix trace, run **`swiftui-expert-skill`** `analyze_trace.py` on the **same run** you append to [baselines/214-trace-macOS-runs.json](./baselines/214-trace-macOS-runs.json).

```bash
# Path on maintainer machine (pi agent skill); adjust if you vendor a copy into scripts/
SWIFTUI_TRACE_SKILL="${SWIFTUI_TRACE_SKILL:-$HOME/.pi/agent/skills/swiftui-expert-skill}"

TRACE="/path/to/your.trace"
RUN=1   # multi-run bundle: xctrace --toc or export script --run N

# Full-session table row (repo exporter)
python3 scripts/export_structured_session_trace_metrics.py \
  --input "$TRACE" --run "$RUN" \
  --output "/tmp/structured-session-run${RUN}.json"

# #225 startup window (0–30 s)
python3 "$SWIFTUI_TRACE_SKILL/scripts/analyze_trace.py" \
  --trace "$TRACE" --run "$RUN" \
  --window 0:30000 --output "/tmp/signoff-225-run${RUN}"

# #224 steady window (skip first 2 min; use same end as long captures ~7 min)
python3 "$SWIFTUI_TRACE_SKILL/scripts/analyze_trace.py" \
  --trace "$TRACE" --run "$RUN" \
  --window 120000:400000 --output "/tmp/signoff-224-run${RUN}"
```

Read `/tmp/signoff-225-run${RUN}.md` and `/tmp/signoff-224-run${RUN}.md` for Time Profiler + animation hitch counts. Compare to [baselines/214-trace-window-analysis.md](./baselines/214-trace-window-analysis.md) sign-off table.

**Pass/fail on one ~5–7 min capture** (baseline = `214.trace` **run 4**):

| Issue | Metric | Pass |
| --- | --- | --- |
| **#225** | `hitches-updates` worst red-marked in first 30 s | **&lt; 296 ms** |
| **#225** | `analyze_trace` `--window 0:30000` worst animation hitch | **&lt; 333 ms** |
| **#224** | `frames_over_33ms_per_minute` from exporter (compute from counts ÷ duration × 60) | **≤ 260** |
| **#224** | `analyze_trace` `--window 120000:400000` animation hitch **count** | **≤ 814** |

Copy `duration_seconds`, `hitches`, and `frames_over_*_per_minute` into a new `runs[]` entry in `214-trace-macOS-runs.json`; set `window_analysis` to the window doc or link issue comment. Comment pass/fail on **#224** and **#225**.

Optional: `python3 "$SWIFTUI_TRACE_SKILL/scripts/analyze_trace.py" --trace "$TRACE" --list-runs` when the bundle has multiple sessions.

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

### Reporter `214.trace` macOS comparison (runs 1 / 3 / 4)

Committed snapshot: [baselines/214-trace-macOS-runs.json](./baselines/214-trace-macOS-runs.json). Run **4** = `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile` after **#221–#223**, ~4.2 min, no parallel `xctest` signposts.

| Run | When | >33 ms frames/min | Worst frame | Worst red hitch |
| --- | --- | --- | --- | --- |
| 1 | Pre #221–#223 | ~27 | 928 ms | 349 ms (~1.2 s) |
| 3 | Post (longer session) | ~202 | 716 ms | 360 ms |
| 4 | Post (clean re-profile) | ~326 | 355 ms | **296 ms** (~1.3 s) |
| 5 | Post **#224–#225** (maintainer, `214.trace`) | **~300** | 442 ms | **350 ms** (~1.23 s) |
| 6 | Post **#224–#225** (latest long, `214.trace`) | **~339** | 372 ms | **308 ms** (~1.26 s) |

Sign-off commands and thresholds: **Windowed analysis** section above. Run **6** (~7.5 min) is the latest long capture in `214.trace`; neither **#224** nor **#225** passes on run 6. If `xctrace export --toc` SIGSEGV on a multi-run bundle, use `--run N` on both exporters only.

**#224 context (code path):** Pi fixture streaming coupled per-tick `liveDraftGrowthToken` → scroll snapshot `onChange` and unbounded live draft layout. Mitigations: `structuredSessionLiveDraftScrollGrowthToken` (96-char buckets), `structuredSessionFeedStreamingAssistantDisplayPolicy` (200 pt viewport). Steady-window stacks: utility `Collection.split` / `String` + frequent *expensive app update(s)* — see [214-trace-window-analysis.md](./baselines/214-trace-window-analysis.md).

### macOS startup red hitch (#225, `214.trace` run 4)

**Dominant stack (trace export, not full Time Profiler):** run 4 worst red-marked hitch **296.23 ms** at **~00:01.289** (`hitches-updates`, swap `0xa258a`). Matching worst frame lifetime **354.67 ms** at **~00:01.256** (`hitches-frame-lifetimes`, same swap id). `swiftui-update-groups` had no rows for this run in CLI export.

**Likely main-thread coupling (code + timing):** first structured feed paint with ~100+ `LazyVStack` chunks, finalized assistant markdown (`StructuredSessionMarkdownText` / typesetter), and redundant `scrollToBottom` on `ScrollView.onAppear` while `ScrollPosition(edge: .bottom)` already anchors the tail.

**Mitigations in tree (#225):** macOS defers mounting `feed.activityRows` until one main-actor turn after feed `ScrollView.onAppear` (`StructuredSessionFeedMacOSStartupPolicy`) so `ScrollPosition(edge: .bottom)` does not couple empty scroll chrome with bulk `LazyVStack` layout in one *expensive app update*; macOS `ScrollPosition(edge: .bottom)` skips all redundant `scrollToBottom` follow work (`scrollPositionUsesBottomEdge` on initial appear and snapshot `onChange`); macOS skips bulk assistant markdown prewarm on full rebuild (row `onAppear` hydration owns first paint; iOS still prewarms); parse/typeset only **bounded** assistant markdown for collapsed long responses (`structuredSessionFeedAssistantMarkdownBoundedPreviewText` in macOS/iOS feed views) so first `LazyVStack` paint does not layout full multiline bodies behind `lineLimit`; macOS sealed chunks are **one row each** (16-row live tail) for presenter tail-rebuild stability (iOS remains 40/8); macOS `ContentView` iterates `feed.activityRows` in one `LazyVStack` (no nested chunk `ForEach`); iOS keeps chunk iteration; macOS `StructuredSessionMarkdownText` shows plain text until row `onAppear`, **yields one main-actor turn** before scheduling hydration, then parses via `StructuredSessionMarkdownRowHydrationScheduler` on a utility background queue with batched main-actor delivery capped at **3 row state updates per flush** (spreads SwiftUI invalidation across run-loop turns when bottom-edge layout materializes many tail rows at once).

Re-profile with the full harness (~5–7 min), then complete **Windowed analysis** (both windows + baseline JSON). **Run 6** is the current long post-fix capture in `214.trace`.

### macOS text layout slice (#220)

Code-side mitigations (automated guardrails + macOS `ContentView`):

- `structuredSessionDetailTextPreview` still bounds row `detailText` at build time (12 lines / 4k chars).
- Finalized assistant markdown uses `structuredSessionFeedAssistantMarkdownDisplayPolicy` (same thresholds as streaming collapse) with a fixed **200 pt** viewport when long.
- System-card markdown `detailText` uses the same bounded viewport as command detail previews.
- Presentation tests: `structuredSessionFeedAssistantMarkdownDisplayPolicyBoundsLongFinalizedResponses` plus existing collapse/detail-preview tests.

After rebuilding macOS Debug from HEAD, re-profile with `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile` and export metrics; compare worst hitch / hitch count to the 09-06 baseline above.

## Related

- Umbrella: GitHub issue **#214**
- macOS perf slices: **#224** (sustained), **#225** (startup red hitch)
- Window stacks + sign-off: [baselines/214-trace-window-analysis.md](./baselines/214-trace-window-analysis.md)
- Automated service baselines: [performance-baselines.md](./performance-baselines.md)
- iOS offscreen mitigations ADR: [adr/0036-structured-session-feed-ios-gpu-offscreen-mitigations.md](./adr/0036-structured-session-feed-ios-gpu-offscreen-mitigations.md)