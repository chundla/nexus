# Structured session display math (#235)

## Scope

- **Full-response reader** (`StructuredSessionAssistantFullResponseReader`, MarkdownUI + LaTeXSwiftUI): renders **display math** on macOS and iOS.
- **Structured feed** (`StructuredSessionMarkdownRenderer`): **plain fallback** when display math is present; users open **Show full response** for rendered math. Inline `$…$` is **#239**, not this slice.

## Delimiter detection

| Form | Opening | Closing | Notes |
| --- | --- | --- | --- |
| Double-dollar | Line `$$` (trimmed) | Line `$$` | Body lines between delimiters become LaTeX |
| Bracket | Line `\[` | Line `\]` | Common TeX display form |

Detection runs line-by-line. Fenced code regions (``` lines) **do not** scan for display math.

## Perf guardrails

- `maxDisplayMathBlocksPerDocument` (default **32**) in `StructuredSessionAssistantFullResponseDisplayMathPolicy`; additional blocks stay in markdown chunks as plain text.
- Feed: `structuredSessionFeedDisplayMathUsesPlainFallback` bypasses AttributedString markdown parse (same bypass counter as plain text) so scroll/hydration policies (#229) are unchanged.
- Reader: LaTeXSwiftUI renders off the main thread; avoid moving display math into the lazy feed (#230).

## References

- ADR 0037, `CONTEXT.md` (hybrid math)
- `Modules/Sources/NexusSessionPresentation/StructuredSessionAssistantFullResponseDisplayMathPolicy.swift`