# Structured session feed inline images (#242)

## Markdown

Assistant **Final answer** and **Reasoning** bodies in the Pi agent-turn stack render `![alt](url)` via `structuredSessionFeedMarkdownContentView` / `structuredSessionFeedFinalAnswerMarkdownView` in `NexusSessionPresentation`.

- Single image: inline preview (lazy `AsyncImage`), tap opens an expanded sheet.
- Multiple images in one markdown body: `TabView` carousel with page index.

Fenced code blocks are not scanned for image syntax.

## Remote Client (iOS)

Image fetches use the device’s network stack against the URL in markdown. **Remote Client** policy (`StructuredSessionFeedRemoteClientImageURLPolicy`) allows only `http` and `https`; `file`, `data`, and other schemes show a placeholder.

Provider-native attachment events are not wired in this slice; markdown URLs are the v1 path.

## Scroll / hydration (#225)

Image rows do not run through `StructuredSessionMarkdownRowHydrationScheduler`. Text segments still use the existing idle-gated markdown path when no images are present.