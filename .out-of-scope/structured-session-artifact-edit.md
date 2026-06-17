# Structured session artifact edit affordance

Nexus will not add a dedicated **Edit** entry point on structured **Session** artifact preview cards until at least one **Provider** exposes a real, provider-native mutation path for that artifact kind (not merely a file on the **Host** filesystem).

## Why this is out of scope (for now)

Today the only feed artifact kind is **Pi exported session HTML**: a one-shot `/export-html` write to a **Host** path surfaced as download/open (#243). There is no Pi RPC to mutate that export in place or sync edits back into the **Session**. **Open** (macOS) and **Download** (Remote **Controller**) already cover the honest actions.

**Provider Capability** today covers launch/create named **Session** actions, not per-artifact mutability. Shipping **Edit** would require inventing capability rules and **Provider Module** edit flows with no provider contract to implement—duplicate of “open in external editor” or an in-app editor with no write-back story.

Product language (**Controller** vs **Viewer**) still applies when mutation exists: only **Controller** when the service reports capability. That gate is straightforward; the missing piece is *what* edit does per **Provider**, which is undefined.

## What would reopen this

- A **Provider Module** documents a concrete mutable artifact kind (RPC or CLI) and Nexus maps it through the single provider seam (ADR 0034).
- Acceptance criteria name that kind, the mutation contract, and tests—not a generic “edit button.”

## Prior requests

- #244 — feat(nexus): artifact edit affordance where Provider allows (epic #245 child)