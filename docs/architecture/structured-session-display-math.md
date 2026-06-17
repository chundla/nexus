# Structured session display math (#235)

## Scope

- **Full-response reader** (`StructuredSessionAssistantFullResponseReader`, MarkdownUI + LaTeXSwiftUI): renders **display math** on macOS and iOS.
- **Structured feed** (`StructuredSessionMarkdownRenderer`): **plain fallback** on the lightweight AttributedString path when display or inline LaTeX is present; Reasoning / Final answer **rich markdown** (`StructuredSessionFeedRichMarkdownView`) renders both after row hydration / idle gate (#229). Inline `$…$` is **#239** (`StructuredSessionAssistantFullResponseInlineMathPolicy`).

## Delimiter detection

| Form | Opening | Closing | Notes |
| --- | --- | --- | --- |
| Double-dollar | Line `$$` (trimmed) | Line `$$` | Body lines between delimiters become LaTeX |
| Bracket | Line `\[` | Line `\]` | Common TeX display form |

Detection runs line-by-line. Fenced code regions (``` lines) **do not** scan for display math.

## Perf guardrails

- `maxDisplayMathBlocksPerDocument` (default **32**) in `StructuredSessionAssistantFullResponseDisplayMathPolicy`; additional blocks stay in markdown chunks as plain text.
- Feed: `structuredSessionFeedLaTeXMathUsesPlainAttributedFallback` bypasses AttributedString markdown parse when display or extracted inline math is present (same bypass counter as plain text) so scroll/hydration policies (#229) are unchanged.
- Inline math: `maxInlineMathExpressionsPerDocument` (default **64**); fenced code ignored; `\$` escapes; unmatched `$` stay literal.
- Reader: LaTeXSwiftUI renders off the main thread; avoid moving display math into the lazy feed (#230).

## References

- ADR 0037, `CONTEXT.md` (hybrid math)
- `Modules/Sources/NexusSessionPresentation/StructuredSessionAssistantFullResponseDisplayMathPolicy.swift`