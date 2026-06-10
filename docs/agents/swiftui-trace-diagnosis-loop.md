# SwiftUI trace diagnosis loop (agents)

Use this workflow for **trace-gated** SwiftUI performance issues (**#224**, **#225**, **#214** umbrella), not the default **`ready-for-agent-tdd`** subagent.

## Pi agent setup

| Piece | Location |
| --- | --- |
| Orchestration skill | `~/.pi/agent/skills/swiftui-trace-diagnosis-loop/SKILL.md` |
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
2. **`swiftui-expert-skill`** — `analyze_trace.py`, optional `record_trace.py` (see below).
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

## Can the agent record its own trace?

**Yes on host Mac**, via `swiftui-expert-skill/scripts/record_trace.py` (`references/trace-recording.md`):

- **Launch** Debug `nexus.app` with `--env NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile` and `--time-limit 7m` after `xcodebuild` build.
- **Attach** to a user-launched `nexus` (Xcode run with same env) for HITL scroll workload.
- **Stop-file** flow: agent starts background record; maintainer scrolls per harness; `touch /tmp/stop-trace`.

**Caveats:**

- Sign-off workload (scroll up, follow bottom, expand/finalize) usually needs **maintainer HITL** during attach recording; launch-only captures startup + fixture ticks, not full harness.
- Use **SwiftUI** template on Mac; confirm trace process path is **DerivedData Debug** `nexus.app`.
- iOS device traces need a physical phone; Simulator uses **Time Profiler** template.

## When to use which subagent

| Issue acceptance | Subagent |
| --- | --- |
| Trace / hitch / Instruments metrics | **`swiftui-trace-diagnosis`** |
| Unit-testable policy / feature slice | **`ready-for-agent-tdd`** |
| General code without perf proof | **`general`** |

## Related

- [issue-tracker.md](./issue-tracker.md)
- [domain.md](./domain.md)
- [performance-baselines.md](../performance-baselines.md)