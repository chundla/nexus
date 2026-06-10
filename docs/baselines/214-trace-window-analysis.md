# `214.trace` windowed analysis (runs 4 vs 6)

Generated with `swiftui-expert-skill` `analyze_trace.py` (not the repo hitch exporter).

```bash
SKILL="${HOME}/.pi/agent/skills/swiftui-expert-skill"
TRACE="214.trace"
# #225 — first 30 s
python3 "$SKILL/scripts/analyze_trace.py" --trace "$TRACE" --run 6 \
  --window 0:30000 --output /tmp/225-run6
# #224 — steady (skip first 2 min)
python3 "$SKILL/scripts/analyze_trace.py" --trace "$TRACE" --run 6 \
  --window 120000:400000 --output /tmp/224-run6
```

Repo aggregate export (full session):

```bash
python3 scripts/export_structured_session_trace_metrics.py --input 214.trace --run 6
```

## #225 startup window (`0:30000` ms)

| Run | Worst animation hitch | Time | Apple label | Correlated main-thread samples |
| --- | --- | --- | --- | --- |
| 4 | **333 ms** | ~1.28 s | Potentially expensive app update(s) | `getMethodNoSuper_nolock`, `objc_msgSend`, dedup symbol |
| 6 | **350 ms** | ~1.24 s | Potentially expensive app update(s) | Same pattern |

Full-session red-marked (`hitches-updates`): run 4 **296 ms** @ ~1.29 s; run 6 **308 ms** @ ~1.26 s.

Time Profiler (30 s): both runs show **AG::Graph::UpdateStack::update()** / **propagate_dirty** in top 15 on main; CPU-bound (100% main coverage on hitch correlations).

`swiftui-causes` / `swiftui-updates` lanes: **0 rows** in CLI export for these runs — invalidation graph not available from trace tables.

**Takeaway (#225):** Startup cluster is still **~1.2–1.3 s**, **Potentially expensive app update(s)**, ObjC dispatch + SwiftUI graph update — not clearly improved vs run 4; run 6 animation worst in window slightly worse than run 4.

## #224 steady window (`120000:400000` ms, ~280 s)

| Run | Animation hitches in window | Worst in window | Time Profiler (dominant) |
| --- | --- | --- | --- |
| 4 | 814 | 92 ms | **Collection.split**, **String** indexing on utility thread (`tid 0x18d0f0`); main: retain/release, `AG::Graph` |
| 6 | **2341** | 42 ms | Same **Collection.split** / **String** stack on `tid 0x1efc75`; ~2.4× hitch count vs run 4 |

Full-session `frames_over_33ms_per_minute` (frame lifetimes): run 4 **326.4**; run 6 **338.7**.

Steady hitch correlations: recurring **swift_retain/release**, **___chkstk_darwin**, **AG::Graph::UpdateStack** — consistent with frequent SwiftUI updates during Pi fixture streaming.

**Takeaway (#224):** Sustained cost is **many small hitches** (42–92 ms), not single giants. Background **string split** work is the largest CPU bucket in the steady window — align with markdown/feed text processing (`StructuredSessionMarkdown*`, bounded preview, hydration). Run 6 is **worse** than run 4 on hitch count in this window.

## Sign-off vs issues

- **#225** acceptance (&lt;296 ms red in first 30 s): run 6 **308 ms** red-marked — **not met**.
- **#224** sustained: run 6 **339/min** full session and higher steady-window hitch count vs run 4 — **not met**.