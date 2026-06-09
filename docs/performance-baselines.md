# Performance baselines

Use this workflow before and after performance work so Nexus changes can be compared against the same baseline capture.

## What is covered

| Flow | Automated baseline | UI-facing observation | Service diagnostic capture |
| --- | --- | --- | --- |
| App launch | `nexusUITests/testLaunchPerformance` | XCTest launch metric in the UI test report | None today |
| Workspace refresh | `NexusServicePerformanceBaselineTests/testWorkspaceRefreshBaseline` | Re-run the same workspace in the macOS app when profiling browse regressions | `workspaceOverview` record |
| Provider Detail open | `NexusServicePerformanceBaselineTests/testProviderDetailOpenBaseline` | Open the same Provider Detail screen in the macOS app when profiling provider browse regressions | `providerDetail` record |
| Session open | `NexusServicePerformanceBaselineTests/testSessionOpenBaseline` | Open the same Session lane in the macOS app when profiling Session entry regressions | `launchDefaultSession` record |
| Structured Session activity append | `NexusServicePerformanceBaselineTests/testStructuredSessionActivityAppendBaseline` | Append the same structured activity in the macOS app when profiling feed update regressions | `structuredSessionObservation` delta record |

## Run the automated baselines

### App launch

Run the existing UI launch performance test:

```bash
xcodebuild test -scheme nexus -project nexus.xcodeproj -destination 'platform=macOS' -only-testing:nexusUITests/nexusUITests/testLaunchPerformance
```

Record the `XCTApplicationLaunchMetric` average from the test output.

### Workspace, Provider, and Session service flows

Run the service baseline suite:

```bash
swift test --package-path Modules --filter NexusServicePerformanceBaselineTests
```

Each baseline test does two things:

1. measures the audited flow with `XCTClockMetric`
2. prints the latest matching `PerformanceDiagnosticRecord` as a `[Baseline] ...` line

Save both the XCTest timing summary and the printed baseline lines when comparing before/after results.

## Audited regression suite

Run this focused suite before and after touching the audited browse and structured **Session** update flows.

### Baseline-aligned service regression checks (#184, #185, #189)

```bash
swift test --package-path Modules --filter NexusServicePerformanceRegressionTests
swift test --package-path Modules --filter NexusServicePerformanceBaselineTests
```

### Structured Session update guardrails (#188, #189, #207)

```bash
swift test --package-path Modules --filter StructuredSessionPresentationTests
swift test --package-path Modules --filter StructuredSessionObservationDiagnosticsTests
swift test --package-path Modules --filter NexusServicePerformanceBaselineTests/testStructuredSessionActivityAppendBaseline
```

### Coverage map and intentional human-only gaps

| Slice | Automated regression coverage | Remaining human-only step |
| --- | --- | --- |
| #185 Workspace refresh batching | `NexusServicePerformanceRegressionTests/testWorkspaceRefreshRegressionMatchesTheAuditedBaselineShape`, `NexusServicePerformanceBaselineTests/testWorkspaceRefreshBaseline`, plus the macOS browse invalidation guardrails below | Re-run the matching macOS profiling flow only when you need a new SwiftUI trace to explain a user-visible regression |
| #186 macOS Workspace browse invalidation | the focused `nexusTests` guardrail command below | Final SwiftUI Instruments validation remains a manual macOS pass |
| #187 iOS Remote Client invalidation | the focused `RemoteClientPairingModelTests` and `RemoteClientProfilingFixtureTests` commands below | Final SwiftUI invalidation tracing still has to run from Xcode Instruments on a physical iPhone |
| #188 structured Session updates | `StructuredSessionPresentationTests`, `StructuredSessionObservationDiagnosticsTests`, `NexusServicePerformanceRegressionTests/testStructuredSessionActivityAppendRegressionMatchesTheAuditedBaselineShape`, and `NexusServicePerformanceBaselineTests/testStructuredSessionActivityAppendBaseline` | None beyond targeted profiling when a regression is still visible after the automated checks |
| #192 long structured Session stall attribution | `StructuredSessionThinkingStallAttributionTests`, `StructuredSessionThinkingStallDiagnosisTests`, and `RemoteClientProfilingFixtureTests/bootstrapStreamsThinkingDiagnosticSnapshotsForLongObservationProfiling` | Final side-by-side memory capture still runs manually on macOS and a physical iPhone when you need Instruments evidence |
| #199 structured Session final-output latency delivery | `StructuredSessionObservationDiagnosticsTests/structuredObservationDeltaRecordsFinalOutputLatencyMetrics`, `StructuredSessionFinalOutputLatencyTrackerTests`, `NexusServicePiSessionStreamTests/localPiRuntimeAttachesFinalOutputLatencyDiagnosticToTurnCompletion`, and `RemoteClientProfilingFixtureTests/bootstrapCapturesFinalOutputLatencyDiagnosticSnapshotsForRemoteClientProfiling` | Final visual trace pairing still runs manually when you need Instruments evidence for the last visible feed update |
| #207 structured feed profiling fixture "evil mode" (real Pi mutation churn) | `NexusAppProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBurstsOnMacOS`, `RemoteClientProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBursts` (both already cover diagnostics + turn progress) | Instruments SwiftUI trace on macOS or physical iPhone to confirm Severe Hang + ScrollViewAdjustedState / ViewLayoutEngine dominance when the fixture now reproduces the full `finalOutputDiagnostic` + `isAgentTurnInProgress` + `providerFacts` (liveAssistantDraftText + tokenUsage) + thinking indicator + `StructuredSessionAutoScrollTrigger` churn on every 200 ms tick (including post-turn_end dwell with continuing seq + notification churn while rows are stable) |

## Diagnostic fields to compare

### Workspace refresh

- operation: `workspaceOverview`
- compare: `totalElapsedMilliseconds`
- compare steps: `loadWorkspace`, `loadRemoteTarget`, `loadSessions.<provider>`, `readProviderCatalog.<provider>`

### Provider Detail open

- operation: `providerDetail`
- compare: `totalElapsedMilliseconds`
- compare steps: `loadWorkspace`, `loadRemoteTarget`, `loadSessions`, `readProviderCatalog`

### Session open

- operation: `launchDefaultSession`
- compare: `totalElapsedMilliseconds`
- compare steps: `loadWorkspace`, `loadDefaultSession`, `planFreshSessionOpen`, `createDefaultSession`, `ensureLaunchSnapshot`, `launchFreshSession`

### Structured Session activity append

- operation: `structuredSessionObservation`
- compare: `totalElapsedMilliseconds`
- compare steps: `buildStructuredDelta`
- compare metrics: `deltaBuildCount`, `changeCount`, `activityItemCount`, `approvalRequestCount`, `fullReplaceFallbackCount`, `structuredRevision`, `transcriptCharacterCount`

### Structured Session final-output delivery

- operation: `structuredSessionObservation`
- compare steps: `buildStructuredDelta` or `buildStructuredSnapshot`
- compare metrics: `finalOutputProviderRuntimeMilliseconds`, `finalOutputServiceObservationMilliseconds`, `finalOutputTriggerTextDeltaCount`, `finalOutputTriggerTurnEndCount`
- compare client snapshot fields: `clientPresentationLatencyMilliseconds`, `totalVisibleLatencyMilliseconds`

## macOS workspace browse invalidation guardrails

Before running a manual SwiftUI profiling pass for the macOS browse surface, run the focused observation-stability tests that guard the extracted browse presentation seams:

```bash
xcodebuild test -scheme nexus -project nexus.xcodeproj -destination 'platform=macOS' \
  -only-testing:nexusTests/appModelWorkspaceHomePresentationStaysStableDuringProviderDetailLoads \
  -only-testing:nexusTests/appModelWorkspaceGroupDetailPresentationStaysStableDuringProviderDetailLoads \
  -only-testing:nexusTests/appModelWorkspaceBrowseSidebarPresentationStaysStableDuringProviderDetailLoads \
  -only-testing:nexusTests/appModelWorkspaceBrowseSidebarPresentationUsesLoadedSessionRoutingForRecentOrdering \
  -only-testing:nexusTests/appModelWorkspaceBrowseNavigationPresentationStaysStableDuringProviderDetailLoads \
  -only-testing:nexusTests/appModelWorkspaceBrowseNavigationPresentationUsesLoadedSessionRoutingForQuickSwitchOrdering \
  -only-testing:nexusTests/appModelWorkspaceBrowseDetailPresentationStaysStableDuringTranscriptOnlyUpdates
```

These tests do not replace SwiftUI Instruments, but they catch service/model observation broadening before you spend time in a profiling trace.

### Repeatable macOS structured feed trace fixture

For the macOS structured-feed hang path, launch the app with:

- `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile`

That fixture opens the macOS app into the real `ContentView` structured-feed surface with:
- one deterministic remote Workspace already loaded
- an initial sidebar selection that targets the Pi structured `Session` directly
- ~100 preseeded structured activity rows spanning multiple chunks
- live draft growth every `200 ms`
- deterministic draft finalization plus the next turn starting automatically
- alternating compact and multi-line command output previews

Suggested trace path:
1. launch the macOS app from Xcode with `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile`
2. let the app settle on the structured `Session` detail screen
3. attach Instruments and capture while the draft expands, finalizes, and starts the next turn
4. compare the trace with `NexusAppProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBurstsOnMacOS`

The fixture now emits the exact live Pi mutation mix that still triggers the hang in 09-06.trace:
- `finalOutputDiagnostic` on turn_end (and re-emitted during post-turn dwell)
- `isAgentTurnInProgress` toggles (true during drafting, false post-turn and during dwell)
- `providerFacts` with changing `liveAssistantDraftText` + `tokenUsage` growth on every tick
- thinking indicator visibility driven by `isAgentTurnInProgress` in presentation
- `StructuredSessionAutoScrollTrigger` changes on (nearly) every observation via rotating extensionUI notifications during drafting AND during the post-turn dwell (while activity rows are stable)

Use this fixture for `ContentView` / macOS structured-feed regressions. Use the `Remote Client` fixture below only for the iPhone path.

## iOS Remote Client invalidation guardrails

Before running a manual SwiftUI profiling pass for the iPhone `Remote Client` browse or focused `Session` surfaces, run the focused observation-stability tests that guard the extracted presentation seams:

```bash
xcodebuildmcp macos test --project-path nexus.xcodeproj --scheme nexus \
  --extra-args -only-testing:nexusTests/RemoteClientPairingModelTests/workspaceBrowsePresentationStaysStableDuringTranscriptOnlyFocusedSessionUpdates \
  --extra-args -only-testing:nexusTests/RemoteClientPairingModelTests/workspaceBrowsePresentationStaysStableDuringPairedMacAvailabilityRefreshes \
  --extra-args -only-testing:nexusTests/RemoteClientPairingModelTests/focusedSessionWorkspaceLocationStaysStableDuringUnrelatedCatalogRefreshes \
  --extra-args -only-testing:nexusTests/RemoteClientProfilingFixtureTests
```

These tests do not replace SwiftUI Instruments, but they catch `Remote Client` browse/session observation broadening and keep the repeatable profiling fixture healthy before you spend time in a profiling trace.

### Repeatable iPhone Remote Client trace fixture

Use one of these deterministic `Remote Client` fixture modes in the iOS run scheme environment:

- `NEXUS_REMOTE_CLIENT_FIXTURE=invalidation-baseline` for browse refreshes plus simple focused `Session` appends
- `NEXUS_REMOTE_CLIENT_FIXTURE=streaming-feed-profile` for the long-running structured-feed stress path with preseeded history, live Pi draft growth, alternating small/large command output, and deterministic turn finalization

A repeatable simulator dry run looks like this:

```bash
xcodebuildmcp simulator build-and-run \
  --project-path nexus.xcodeproj \
  --scheme nexus \
  --simulator-id ECA0B50A-0AC8-479A-B26B-F48E05077E3B

xcodebuildmcp simulator launch-app --json '{
  "simulatorId": "ECA0B50A-0AC8-479A-B26B-F48E05077E3B",
  "bundleId": "com.chundla.nexus",
  "env": {
    "NEXUS_REMOTE_CLIENT_FIXTURE": "streaming-feed-profile"
  }
}'
```

The `invalidation-baseline` fixture starts with:
- one active **Paired Mac** already selected and reachable
- a two-Workspace `Workspace Catalog` already available after refresh
- a launchable Pi structured **Session** in `Baseline API`
- automatic transcript-only focused `Session` updates after you open that conversation

The `streaming-feed-profile` fixture keeps the same navigation shape, but the conversation opens into a heavier structured-feed scenario:
- ~100 preseeded structured activity rows spanning multiple chunks
- deterministic live Pi draft growth every `200 ms`
- finalized assistant responses that preserve the live row identity
- alternating compact and multi-line command output previews on each completed turn

Suggested trace paths:
1. use `invalidation-baseline` when you need `Paired Mac` / `Workspace Catalog` refresh invalidation evidence
2. use `streaming-feed-profile` when you need live structured-feed layout evidence:
   - open `Baseline API` → `Pi` → **Open conversation**
   - leave the trace running while the draft expands, finalizes, and starts the next turn automatically
   - compare the trace with `RemoteClientProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBursts`

Important: `xcrun xctrace` currently reports `The SwiftUI instrument is not supported on the Simulator` for this app flow, so use the simulator fixture for deterministic navigation rehearsal and focused test validation, but run the final SwiftUI invalidation trace from Xcode Instruments on a physical iPhone.

## Structured Session final-output latency diagnosis (#199)

Use this loop when a structured **Session** finishes provider work but the final answer feels slow to appear in the visible feed and you need to decide whether the delay came from provider/runtime projection, service-side structured observation bookkeeping, or client **Session Presentation**.

### Automated guardrails

```bash
swift test --package-path Modules --filter StructuredSessionObservationDiagnosticsTests/structuredObservationDeltaRecordsFinalOutputLatencyMetrics
swift test --package-path Modules --filter StructuredSessionFinalOutputLatencyTrackerTests
swift test --package-path Modules --filter NexusServicePiSessionStreamTests/localPiRuntimeAttachesFinalOutputLatencyDiagnosticToTurnCompletion
xcodebuildmcp macos test --project-path nexus.xcodeproj --scheme nexus \
  --extra-args -only-testing:nexusTests/RemoteClientProfilingFixtureTests/bootstrapCapturesFinalOutputLatencyDiagnosticSnapshotsForRemoteClientProfiling
```

- `StructuredSessionObservationDiagnosticsTests/structuredObservationDeltaRecordsFinalOutputLatencyMetrics` verifies that `structuredSessionObservation` diagnostics record `finalOutputProviderRuntimeMilliseconds`, `finalOutputServiceObservationMilliseconds`, and the `textDelta` / `turnEnd` trigger counters.
- `StructuredSessionFinalOutputLatencyTrackerTests` verifies the shared client-side latency tracker that turns canonical final-output milestones into visible-feed presentation timing.
- `NexusServicePiSessionStreamTests/localPiRuntimeAttachesFinalOutputLatencyDiagnosticToTurnCompletion` proves the Pi runtime attaches final-output timing anchors when a real `turn_end` completion lands.
- `RemoteClientProfilingFixtureTests/bootstrapCapturesFinalOutputLatencyDiagnosticSnapshotsForRemoteClientProfiling` keeps the iPhone `Remote Client` fixture healthy while a focused reply records visible-feed final-output latency.

### Repeatable evidence to compare

Capture the latest `structuredSessionObservation` diagnostic record with `metrics["finalOutputLatencyCount"] == 1` and compare it with a current client snapshot.

Service-side fields:

- `finalOutputProviderRuntimeMilliseconds`: provider event handling plus runtime projection into shared `SessionScreen`
- `finalOutputServiceObservationMilliseconds`: elapsed time from that projected screen state until structured observation work picked it up
- `buildStructuredDelta` / `buildStructuredSnapshot`: structured observation build cost for the same update
- `finalOutputTriggerTextDeltaCount` / `finalOutputTriggerTurnEndCount`: which provider milestone produced the visible feed update

Client-side fields:

- macOS: `NexusAppModel.focusedStructuredSessionDiagnosticSnapshot?.finalOutputLatency`
- iPhone `Remote Client`: `RemoteClientPairingModel.focusedStructuredSessionDiagnosticSnapshot?.finalOutputLatency`
- `clientPresentationLatencyMilliseconds`: time from the observed canonical final-output milestone to the matching visible feed row in shared **Session Presentation**
- `totalVisibleLatencyMilliseconds`: provider/runtime + service observation + client presentation time combined

Interpretation:

- high `finalOutputProviderRuntimeMilliseconds` with low follow-on numbers ⇒ provider/runtime projection cost
- low provider/runtime time but high `finalOutputServiceObservationMilliseconds` or `buildStructuredDelta` ⇒ service observation/bookkeeping cost
- low service numbers but high `clientPresentationLatencyMilliseconds` ⇒ client **Session Presentation** cost

For final manual captures, pair those counters with a matching Instruments trace on macOS or a physical iPhone so the visible feed update lines up with the repeatable timing sample above.

## Long structured Session stall diagnosis (#192)

Use this loop when a structured **Session** appears stuck in `Thinking…` and you need to decide whether the stall is in the provider runtime, the shared observation path, or client **Session Presentation**.

### Automated guardrails

```bash
swift test --package-path Modules --filter StructuredSessionThinkingStallAttributionTests
swift test --package-path Modules --filter StructuredSessionThinkingStallDiagnosisTests
xcodebuildmcp macos test --project-path nexus.xcodeproj --scheme nexus \
  --extra-args -only-testing:nexusTests/RemoteClientProfilingFixtureTests/bootstrapStreamsThinkingDiagnosticSnapshotsForLongObservationProfiling
```

- `StructuredSessionThinkingStallAttributionTests` verifies the shared attribution rules:
  - no canonical progress while `Thinking…` stays visible ⇒ runtime stall
  - canonical progress without observed screen progress ⇒ observation-layer stall
  - observed screen progress without **Session Presentation** progress ⇒ client projection stall
- `StructuredSessionThinkingStallDiagnosisTests` drives a repeatable macOS **Background Service** structured **Session** fixture and proves canonical history growth can be attributed to the observation layer when the client side is held still
- `RemoteClientProfilingFixtureTests/bootstrapStreamsThinkingDiagnosticSnapshotsForLongObservationProfiling` keeps the iPhone `Remote Client` fixture healthy while it streams a long-running structured `Thinking…` turn

### Repeatable evidence to compare

Capture two samples a short interval apart:

- macOS canonical sample: `StructuredSessionObservationProgressSample(screen: snapshot.screen, structuredRevision: snapshot.structuredSnapshot?.revision)` from `getSessionScreenObservationSnapshot`
- iPhone client sample: `model.focusedStructuredSessionDiagnosticSnapshot`
- attribution: `structuredSessionThinkingStallAttribution(...)`

The shared samples use repeatable counts as the lightweight memory-growth evidence for this slice:

- transcript character count
- activity item / activity row count
- approval request count
- provider event count
- last visible activity text
- whether `Thinking…` is still active

Interpretation:

- `.runtime`: canonical macOS state stopped advancing while `Thinking…` stayed active
- `.observation`: the macOS canonical sample advanced, but the observed client sample did not
- `.sessionPresentation`: the observed client sample advanced, but the client **Session Presentation** did not

For final manual captures, pair the macOS canonical sample deltas with Instruments memory graphs on macOS or a physical iPhone so the qualitative trace lines up with the repeatable counters above.

## Structured Session live trace harness (#219)

For repeatable **SwiftUI** hitch exports on the 09-06-style structured-feed workload (macOS `NEXUS_MAC_PROFILE_FIXTURE=structured-feed-profile`, iOS device `NEXUS_REMOTE_CLIENT_FIXTURE=streaming-feed-profile`), see [structured-session-instruments-harness.md](./structured-session-instruments-harness.md).

## Profiling guidance

Use the automated baselines first. If a regression is user-visible, then profile the matching macOS app flow on the same machine and branch so the UI trace can be compared with the service baseline output above.

Keep captures comparable:

- use the same machine
- avoid running broad background work during captures
- compare the same audited flow, not a nearby path
- keep the baseline test iteration count unchanged unless you intentionally reset the baseline workflow
