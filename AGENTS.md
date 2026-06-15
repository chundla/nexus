# AGENTS.md

## Response Style

Be ruthlessly concise. Give direct answers only. No fluff, intros, summaries, "Great question", hedging, or filler. Lead with the core answer or action. Be opinionated when relevant—pick a side and own it. Use short sentences. Bullet or numbered lists for steps/options. Swearing OK if it fits naturally. Call out bad ideas bluntly but helpfully. No moralizing, corporate-speak, or unsolicited advice.

Prioritize:
- Usefulness over politeness
- Brevity (cut every unnecessary word)
- Actionable outputs (commands, code, scripts ready to copy-paste)
- Clarity first

If the user wants more detail, they will ask. Default to minimal viable response.

## Project overview

Nexus is a **workspace-first** macOS control center for coding agent CLIs (local and remote). The **Background Service** owns orchestration, persistence, provider adapters, and session lifecycle; the macOS app talks to it over local IPC.

**Core vocabulary** (use these terms; see `CONTEXT.md` for definitions and synonyms to avoid): **Workspace**, **Provider**, **Session**, **Session Record**, **Host**, **Remote Workspace**, **Paired Mac**, **Remote Client**, **Controller** / **Viewer**.

**Where truth lives:**
- Product language: `CONTEXT.md`
- Stable architecture: `ARCHITECTURE.md`, `docs/architecture/domain-model.md`
- Rollout slices: `docs/architecture/milestone-*.md` — prefer **`milestone-14.md`** (newest) over older future-tense text
- Durable decisions: `docs/adr/`
- Quick orientation: `README.md`

**Repo layout:**
- `nexus/` — macOS app target
- `Modules/Sources/NexusDomain` — shared domain types
- `Modules/Sources/NexusIPC` — local IPC contracts
- `Modules/Sources/NexusService` — service orchestration, persistence, provider modules, session runtime
- `Modules/Sources/NexusSessionPresentation` — structured session presentation models
- `docs/architecture/`, `docs/adr/`, `docs/prd/`

SwiftPM package: `Modules/Package.swift` (Swift tools 6.0, macOS 10.15+). Most service/domain tests run via `swift test --package-path Modules`.

## Build and test commands

**macOS app (Xcode):**

```bash
xcodebuild -scheme nexus -project nexus.xcodeproj build
xcodebuild test -scheme nexus -project nexus.xcodeproj -destination 'platform=macOS'
```

**Focused module tests (preferred for small changes):**

```bash
swift test --package-path Modules --filter <TestTypeOrMethodName>
```

**Swift lint (before PR; matches CI):**

```bash
./scripts/lint-swift.sh
```

Strict on `swift format lint` and SwiftLint `force_try` only. After editing Swift, you may run `swift format -i` on touched files.

**Performance / baseline workflows:** `docs/performance-baselines.md` (Xcode UI launch tests, `NexusServicePerformanceBaselineTests`, Instruments harness in `docs/structured-session-instruments-harness.md`).

For Xcode/iOS/macOS tasks, prefer **XcodeBuildMCP** (`xcodebuildmcp`) over raw `xcodebuild` when the skill is available.

### Building and testing (agent rules)

- Do not run test commands with `bash` `usePTY=true`.
- Cap tool timeouts initially at **120s**; increase only for that specific run if the command is actively progressing. Do not default to long timeouts (e.g. 1200s).
- Do not run multiple SwiftPM or XcodeBuildMCP test commands **in parallel** — shared build state contends on locks.
- Prefer narrow `swift test --filter ...` over broad suite filters; if a filtered run times out, narrow the filter before assuming failure.

## Code style guidelines

- **Swift 6** concurrency: respect `Sendable`, actor isolation, and `@MainActor` for UI and main-thread-only types. Use `@unchecked Sendable` only with clear justification (often test doubles / transport boundaries).
- **Domain language:** name types, tests, issues, and APIs with terms from `CONTEXT.md` (**Session**, not tab/process; **Provider**, not tool/backend).
- **Architecture:** UI is not authoritative — **Background Service** owns state, persistence, provider health, and session lifecycle. Provider-specific behavior goes through the **Provider Module** seam in the service, not duplicated in the app.
- **ADRs:** if a change contradicts `docs/adr/`, call it out explicitly; do not silently override.
- Match existing file and module boundaries; extend `NexusDomain` / `NexusService` / app targets rather than introducing parallel type systems.

## Testing instructions

- **Default validation:** one focused `swift test --filter ...` or a single Xcode test class/method tied to the change.
- **App + IPC integration:** `nexusTests/` and `xcodebuild test` on scheme `nexus`.
- **Structured session / Pi / Codex paths:** heavy coverage lives under `Modules/Tests/NexusServiceTests` and related presentation tests — grep for the feature name before adding duplicate fixtures.
- **UI / launch performance:** `nexusUITests`, documented in `docs/performance-baselines.md`.
- **TDD:** use `/skill:tdd` when the user wants red-green-refactor or test-first work.
- **Regression:** after behavior changes, run the narrowest test that would have caught the bug; broaden only if the change crosses module boundaries.

## Security considerations

- **No Nexus-owned secret vault** for SSH: remote access is **SSH-config-first**; Nexus reuses the user’s existing SSH setup (see PRD / milestone docs). Do not add password or private-key storage features without an explicit ADR and product decision.
- **Provider authentication stays provider-native** — Nexus does not reimplement Codex/Claude/Pi/Bob login flows; **Provider Health** surfaces auth-blocked states truthfully.
- **Remote Client pairing** is local-network, durable device trust — not a cloud account system. Do not log pairing secrets, tokens, or raw credentials in tests or diagnostics.
- **Execution authority** stays on the Mac **Background Service**; remote workspaces execute on the **Host**, not on the phone client.
- Treat user workspace paths, hostnames, and session content as sensitive in logs and test output; avoid committing real paths or credentials.

## Workflow

### Commits

- Always create a commit after you have made changes or additions to any code or documentation.
- Prefer **conventional commits** matching recent history: `type(scope): summary` (e.g. `fix(macOS): …`, `test(Modules): …`, `docs(perf): …`). Reference issue numbers in the body or suffix when relevant (`#123`).

### Pull requests

- Keep PRs scoped to one vertical slice when possible; link the GitHub issue.
- Note doc or ADR updates when behavior or domain language changes.
- Call out concurrency, IPC, or persistence migrations explicitly in the description.

### Issue Tracker

Issues are tracked in GitHub Issues for this repo. See `docs/agents/issue-tracker.md`.

- When creating or editing GitHub issue bodies from shell heredocs, use a single-quoted heredoc delimiter (for example `<<'EOF'`) so backticks and other Markdown syntax are not evaluated by the shell.

### Triage Labels

Use the default triage label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain Docs

This repo uses a single-context domain-docs layout. See `docs/agents/domain.md`.

Before exploring unfamiliar areas: read `CONTEXT.md` and relevant `docs/adr/` entries. Use glossary terms in issue titles and test names.

## Tools

### XcodeBuildMCP

- For Xcode/iOS/macOS build, run, and test tasks, prefer the `xcodebuildmcp` CLI over raw `xcodebuild` when possible.
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.

### Swift / SwiftUI work

- Concurrency fixes and reviews: `/skill:swift-concurrency-expert`
- SwiftUI performance or Liquid Glass: relevant skills under `swiftui-*` when the task is UI-heavy
- **Trace-gated SwiftUI perf** (Instruments / hitch acceptance): `docs/agents/swiftui-trace-diagnosis-loop.md` — not the default **tdd** subagent

### iOS device: structured-feed trace + mirroir (gotchas)

Full harness: `docs/structured-session-instruments-harness.md`. Parser RAM / lanes: **swiftui-expert-skill** `references/trace-analysis.md`.

**Fixture on device** — `NEXUS_REMOTE_CLIENT_FIXTURE=streaming-feed-profile` must be set when the app **starts** (not mid-attach):

```bash
xcodebuildmcp device build-and-run --project-path nexus.xcodeproj --scheme nexus \
  --device-id <UDID> --json '{"env":{"NEXUS_REMOTE_CLIENT_FIXTURE":"streaming-feed-profile"}}'
```

`xctrace --env` applies only to **`--launch`**, not **`--attach`**. Relaunch with env if the feed looks like production, not profiling fixture.

**Recording (physical iPhone, SwiftUI template)**

- **Do not** `xctrace --launch` a Mac-path `.app` from XcodeBuildMCP DerivedData for device — launch fails (`FBSApplicationLibrary` nil). Use **attach** to an already-installed app.
- **One** `xctrace record` at a time: `pkill -f 'xctrace record'` (and close Xcode Instruments) before starting; otherwise **`_lockKPerf`** → ~1s or empty traces (“Missing Template”, not analyzable).
- Do **not** start a second `record_trace.py` in the background while another attach is running.
- Attach target name on device is typically **`Nexus`**; device **`IBMiPhoneski`** (or UDID from `record_trace.py --list-devices` / `xcodebuildmcp device list`).
- After a **`--time-limit`** capture ends, **do not kill `xctrace` early**. Finalisation can take **~2 minutes** on device SwiftUI traces. Wait for `record_trace.py` to print `done. trace written:` and verify `xcrun xctrace export --toc` works before assuming the trace is usable.

```bash
pkill -f 'xctrace record'; sleep 3
python3 "$HOME/.pi/agent/skills/swiftui-expert-skill/scripts/record_trace.py" \
  --device IBMiPhoneski --attach Nexus --time-limit 60s \
  --output traces/ios-post-fix.trace
```

**During record:** mirroir — Baseline API → Pi → Open conversation → ~8s settle → scroll up → scroll back to bottom (scroll hitch repro). **`~/.mirroir-mcp/permissions.json`** must allow `tap`/`swipe`; restart mirroir MCP after creating/editing it (default is fail-closed, read-only tools only).

**Analyze** — reject traces with `duration_s` ≪ 60 or export “Missing Template”. Prefer phased parse:

```bash
python3 "$HOME/.pi/agent/skills/swiftui-expert-skill/scripts/analyze_trace.py" \
  --trace traces/ios-post-fix.trace \
  --lanes hitches,hangs,swiftui,swiftui-causes --no-correlate --json-only
```

**Window intent:** **0–30s** = startup (#225); **~45–60s** with nav ending in scroll-to-bottom = scroll hitch repro; **5–7 min** = harness sign-off (#224 steady window).