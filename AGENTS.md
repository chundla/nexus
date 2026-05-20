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
