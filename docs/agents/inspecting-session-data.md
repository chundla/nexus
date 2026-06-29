# Inspecting Session data when the user reports a bad session

When the user says "this session was wrong/broken/garbled" and points at a specific
Workspace/Session, don't just re-read the runtime code — pull the actual persisted
state for that Session out of the Background Service's store first. That's ground
truth for what the service rendered/recorded, independent of whatever the bug theory is.

## Where the data lives

All on the Mac running the Background Service, under:

```
~/Library/Application Support/Nexus/
├── Nexus.sqlite                  # Session/Workspace/Provider metadata (SQLite)
└── PiStructuredSessionHistory/   # Per-session structured activity history (JSON/JSONL)
    └── <session-uuid>/
        ├── current.json          # Latest persisted SessionActivityItem / approvals / provider events
        ├── activity-items.jsonl  # Overflow log of older activity items (paged out of current.json)
        └── provider-events.jsonl # Overflow log of older provider events
```

This is the **real production store** the running app/service uses — not a test
fixture. Treat session content, workspace paths, and hostnames as sensitive; don't
paste raw contents into issues/PRs without redacting.

`Nexus.sqlite` can be large (100s of MB) on an active dev machine. Always query it
read-only.

## 1. Find the Session ID and Workspace

Ask the user for the Workspace name (or grep `sessions.name`), then look it up:

```bash
sqlite3 -readonly "$HOME/Library/Application Support/Nexus/Nexus.sqlite" <<'SQL'
.headers on
.mode column
SELECT s.id, s.name, s.state, s.failure_message, s.provider_id, w.name AS workspace
FROM sessions s
JOIN workspaces w ON w.id = s.workspace_id
WHERE w.name LIKE '%<workspace-substring>%'
ORDER BY s.name;
SQL
```

Key columns on `sessions`: `id`, `workspace_id`, `provider_id`, `name`, `state`
(`running`/`failed`/etc.), `failure_message`, `terminal_columns`/`terminal_rows`.

Related tables worth checking for the same Session ID:
- `session_record_adapter_metadata` — provider-specific adapter metadata JSON blob
- `launch_snapshots` — resolved executable/working directory used to launch it
- `provider_health_snapshots` / `host_validation_snapshots` — was the Provider/Host
  unhealthy around the time of the report

## 2. Read the structured activity history for that Session ID

```bash
SESSION_ID="<uuid-from-step-1>"
HISTORY_DIR="$HOME/Library/Application Support/Nexus/PiStructuredSessionHistory/$SESSION_ID"

cat "$HISTORY_DIR/current.json" | python3 -m json.tool | less
```

`current.json` decodes to `PiStructuredSessionPersistedState`
(`Modules/Sources/NexusService/PiStructuredSessionHistoryStore.swift`):
`activityItems`, `approvalRequests`, `extensionUIState`, `providerEvents`. This is
only populated for Sessions whose `primarySurface == .structuredActivityFeed`
(structured providers, e.g. Pi/Codex/Bob) — terminal-surface Sessions won't have a
directory here at all, since their content lives in the live terminal transcript
instead.

If `current.json` looks too short relative to what the user saw, check the overflow
files — older items get paged out of `current.json` into these JSONL logs by
`StructuredSessionLiveHistoryRetention`:

```bash
cat "$HISTORY_DIR/activity-items.jsonl" | python3 -c 'import sys,json; [print(json.dumps(json.loads(l), indent=2)) for l in sys.stdin]'
cat "$HISTORY_DIR/provider-events.jsonl" | python3 -c 'import sys,json; [print(json.dumps(json.loads(l), indent=2)) for l in sys.stdin]'
```

## 3. Correlate with diagnostics tables

If the report involves a Remote Client (phone) or a perf complaint, also check:

```bash
sqlite3 -readonly "$HOME/Library/Application Support/Nexus/Nexus.sqlite" <<'SQL'
.headers on
.mode column
SELECT * FROM remote_client_diagnostic_breadcrumbs
WHERE session_id = '<uuid>' ORDER BY recorded_at DESC LIMIT 50;

SELECT * FROM performance_diagnostics
WHERE session_id = '<uuid>' ORDER BY recorded_at DESC LIMIT 50;
SQL
```

## Don't write to these files

Read-only. The Background Service owns this store; mutating it out-of-band (even to
"fix" a bad session for a repro) will desync it from the service's in-memory state
and SQLite's own bookkeeping. If you need a clean repro, use
`NexusService.bootstrapForTests(rootURL:)` against a temp directory instead.
