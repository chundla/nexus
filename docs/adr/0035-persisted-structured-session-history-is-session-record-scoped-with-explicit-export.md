# ADR 0035: Persisted structured Session history is Session Record scoped, with explicit export

## Status
Accepted

## Decision

Nexus keeps bounded live structured `SessionScreen` state separate from persisted structured **Session** history.

- Live structured `SessionScreen` payloads stay bounded for shared rendering, observation, and iPhone/macOS attachment performance.
- Persisted structured **Session** history is service-owned local data on the owning Mac that exists so Nexus can reopen, recover, and page structured **Sessions** after those live bounds are trimmed.
- The default retention scope for persisted structured **Session** history is the lifetime of the owning **Session Record**.
- Deleting a **Session Record** deletes its persisted structured history.
- A narrower explicit lifecycle flow may discard or move persisted structured history earlier when the product meaning is "start fresh" or "replace this record with that record".
- Persisted structured **Session** history is not an automatic full-capture or export guarantee.
- Export remains an explicit provider-native action or future product feature, separate from the default retained-history behavior.

This extends ADR-0019's bounded-live-vs-full-capture separation into protocol-native structured **Sessions**.

## Consequences

- macOS and iPhone clients can rely on persisted structured history for reopen and paging without requiring unbounded live `SessionScreen` memory.
- Privacy and storage tradeoffs stay explicit: Nexus stores more than the bounded live view on the owning Mac, but it does not automatically create broad export artifacts as a side effect of normal structured **Session** use.
- Users who want full capture or shareable artifacts still need an explicit export path instead of assuming retained structured history is equivalent to export.
- Future retention settings may add tighter cleanup controls or explicit export management, but the default behavior remains Session-Record-scoped retention.
