## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default triage label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain-docs layout. See `docs/agents/domain.md`.

### Testing

- Do not run test commands with `bash` `usePTY=true`.
- Run `xcodebuild test` and other test commands without PTY to avoid interrupted/invalid runs.
- Cap tool timeouts at `120s` max. Do not use longer timeouts like `1200s`.
- Do not run multiple SwiftPM or Xcode test commands in parallel; they can contend on shared build state, wait on locks, and burn the timeout budget.
- When validating a focused change, prefer narrow single-test `swift test --filter ...` runs over broad suite-level filters. If a broad filtered run times out, retry with a narrower filter before assuming the code is slow or failing.

### Rules

- Always create a commit after you have made changes or additions to any code or documentation.
