# 0036. Structured session feed: iOS GPU offscreen pass mitigations

## Status

Accepted

## Context

Parent trace (#214): iOS hitch ~3:59 with **109 offscreen render passes** plus expensive GPU during structured session feed scroll/stream.

Audit of `RemoteClientHomeView` activity row path and shared `StructuredSessionMarkdownText`:

| Contributor | Why it hurts scroll |
|-------------|---------------------|
| Per-row `.textSelection(.enabled)` on feed text (iOS only) | Selection overlay work scales with visible multiline rows |
| Nested shapes per row (rounded rects, capsules, detail inset) | Each row is multiple layers re-rasterized while scrolling |
| `StructuredSessionMarkdownText` attributed `Text` | Heavier than plain `Text`; already cached; still participates in row layer tree |
| Composer `.ultraThinMaterial` | Blur over feed edge; not per-row; left unchanged |
| Terminal nested `ScrollView([.horizontal, .vertical])` | Separate surface; out of structured feed scope |

macOS already disabled feed text selection for layout stability (same overlay class of problem).

## Decision

1. **Disable structured feed text selection on iOS** — align `StructuredSessionFeedTextSelectionPolicy` to `false` on all platforms for feed content. Users can still copy from macOS host or future dedicated export; feed is not a copy surface during live scroll.

2. **iOS row `compositingGroup()`** — apply `structuredSessionFeedRowCompositing()` on each activity row role container so bubble chrome flattens to one composited layer per row.

3. **Match macOS text sizing** — use `structuredSessionFeedTextSelection()` + `fixedSize(horizontal: false, vertical: true)` on iOS plain feed text where macOS already does, to avoid redundant measurement passes.

## Verification

Re-capture iOS Instruments SwiftUI trace with the same session script as `09-06.trace`; compare offscreen pass count on worst hitch during steady scroll/stream. Target: no triple-digit offscreen passes in comparable capture.

## Consequences

- Feed text on iOS remote client is not selectable in-session (acceptable trade for scroll GPU).
- macOS feed behavior unchanged except shared policy documentation.