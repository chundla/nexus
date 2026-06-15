# 0037. Structured session feed uses composite agent-turn segments

## Status

Accepted

## Context

Structured **Session** feeds on macOS and the iOS **Remote Client** today iterate one scroll item per `StructuredSessionActivityRow`. Pi (and later Codex, IBM Bob) emit reasoning (`thoughts:` status), tool execution (`command` + detail), and assistant replies as separate activity items. Product goal is Grok/ChatGPT-style **turn stacks**: user bubble, then Reasoning / Tools / Final answer accordions—not a flat interleaved timeline.

Alternatives considered: (1) client-only visual grouping over flat rows—rejected because macOS/iOS would diverge and scroll/history identity would stay tied to pre-group row counts; (2) a single synthetic activity row embedding the stack—rejected because it obscures scroll targets and chunks for paging (#225, #208).

Grill decisions live in `CONTEXT.md` (agent turn boundaries, split row placement, tools/reasoning disclosure defaults, approvals outside the stack).

## Decision

1. **Session Presentation** (`NexusSessionPresentation`) projects the structured feed as **composite feed segments**: user message, **agent turn** stack, and standalone rows outside the stack. Reasoning and tool rows are **not** separate lazy-feed scroll items in this projection. Canonical `SessionScreen.activityItems` stays complete for the **Background Service**, persistence, and history paging.

2. **Agent turn** boundaries are **hybrid**: prompt-anchored user `message` rows (`prompt` set or canonical user prefix) for history; the live tail attaches in-progress assistant draft and in-flight tool output to the **open** turn while agent work is active.

3. **Split placement** inside a turn: **Reasoning** ← `thoughts:` status (merged, markdown); **Tools** ← tool-execution commands, nested subagent output, structured fields + optional raw JSON; **Final answer** ← primary assistant message for the turn. User slash echoes, compaction/retry banners, and similar stay **outside** the stack. **Approval Requests** stay in session chrome, not inside the turn stack.

4. **macOS and iOS** ship the same segment shape and turn-stack UI in the Pi v1 slice (shared presentation; platform adapters only).

5. **Rich markdown** for Pi v1 extends the lightweight feed renderer (fenced code → custom SwiftUI blocks with copy); display math (`$$…$$`) lands in the MarkdownUI full-response reader first; feed math and inline `$…$` are follow-ups. Do not move the entire lazy feed to MarkdownUI (#230 guardrails).

## Consequences

- Feed scroll policies (progressive tail reveal, pin-to-bottom, inline markdown idle gate) must key off **segment** identity and count, not raw activity row count.
- Provider rollout order: Pi rules first in presentation, then Codex, then IBM Bob turn mapping slices.
- Per-turn DisclosureGroup expansion is sticky in client state for the attached **Session** lifetime only—not persisted on **Session Record**.