# SwiftUI trace diagnosis loop (agents)

**Generic loop + trace record/analyze:** `~/.pi/agent/skills/swiftui-trace-diagnosis-loop/SKILL.md` and subagent **`swiftui-trace-diagnosis`** (any repo). This file is the **Nexus overlay** (harness, windows, baselines).

Use for **trace-gated** SwiftUI perf, not **`ready-for-agent-tdd`** by default.

## Pi agent setup

| Piece | Location |
| --- | --- |
| Orchestration skill (generic) | `~/.pi/agent/skills/swiftui-trace-diagnosis-loop/SKILL.md` |
| Subagent | `~/.pi/agent/agents/swiftui-trace-diagnosis.md` |

Parent delegates with:

```text
subagent swiftui-trace-diagnosis
/skill:swiftui-trace-diagnosis-loop
Issue #224: one hypothesis — reduce steady-window animation hitches vs 214.trace run 4.
Optional trace: 214.trace run 6 for differential only; new trace required for sign-off.
```

## Nested skills (mandatory)

1. **`diagnose`** — perf feedback loop, ranked hypotheses, one change per trace, verify on original repro.
2. **`swiftui-expert-skill`** — `analyze_trace.py`, `record_trace.py` (launch/attach/stop-file — documented in the generic skill).
3. **`swiftui-performance-audit`** — code-first review **after** trace narrows files, **before** edit.

**Not** **`tdd`** as the lead loop unless the slice is an explicit policy test (e.g. scroll growth bucket).

## Nexus harness (structured Session feed, macOS)

Full steps: [structured-session-instruments-harness.md](../structured-session-instruments-harness.md).

| Step | Command / artifact |
| --- | --- |
| Pre-flight | `NexusAppProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBurstsOnMacOS` |
| Env | `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile` |
| Aggregate metrics | `scripts/export_structured_session_trace_metrics.py` |
| Windowed sign-off | `swiftui-expert-skill/scripts/analyze_trace.py` windows `0:30000` (#225), `120000:400000` (#224) |
| Baselines | `docs/baselines/214-trace-macOS-runs.json`, `docs/baselines/214-trace-window-analysis.md` |

Acceptance thresholds are on GitHub **#224** / **#225** bodies (run **4** baseline, not run 1 ~27/min).

## Nexus: recording traces

Generic commands: generic skill § **Recording traces**. Nexus-specific:

```bash
xcodebuild -scheme nexus -project nexus.xcodeproj -configuration Debug -destination 'platform=macOS' build
APP="$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/nexus.app' -type d 2>/dev/null | head -1)"
SWIFTUI_TRACE_SKILL="${SWIFTUI_TRACE_SKILL:-$HOME/.pi/agent/skills/swiftui-expert-skill}"

# Launch + fixture (startup + ticks; scroll often needs attach + HITL)
python3 "$SWIFTUI_TRACE_SKILL/scripts/record_trace.py" --launch "$APP" \
  --env NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile --time-limit 7m --output /tmp/nexus-feed.trace

# Attach after Xcode Run with same env; maintainer does harness scroll → touch /tmp/stop-trace if using --stop-file
python3 "$SWIFTUI_TRACE_SKILL/scripts/record_trace.py" --attach nexus --time-limit 7m --output /tmp/nexus-feed.trace
```

Confirm trace process path is **DerivedData Debug** `nexus.app`. Full harness workload: [structured-session-instruments-harness.md](../structured-session-instruments-harness.md).

## When to use which subagent

| Issue acceptance | Subagent |
| --- | --- |
| Trace / hitch / Instruments metrics | **`swiftui-trace-diagnosis`** |
| Unit-testable policy / feature slice | **`ready-for-agent-tdd`** |
| General code without perf proof | **`general`** |

## `ready-for-agent-loop` / `rfa` prompt

Parent prompt (`~/.pi/agent/prompts/ready-for-agent-loop.md`) processes **`bug` + `ready-for-agent`** before **`enhancement` + `ready-for-agent`**, then **`needs-triage`**. It routes trace-gated issues to **`swiftui-trace-diagnosis`** + `/skill:swiftui-trace-diagnosis-loop`; everything else stays on TDD. Label perf regressions **`bug`**, not **`enhancement`**, when acceptance is trace sign-off.

## Related

- [issue-tracker.md](./issue-tracker.md)
- [domain.md](./domain.md)
- [performance-baselines.md](../performance-baselines.md)