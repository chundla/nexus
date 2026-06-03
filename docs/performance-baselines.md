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

## iOS Remote Client invalidation guardrails

Before running a manual SwiftUI profiling pass for the iPhone `Remote Client` browse or focused `Session` surfaces, run the focused observation-stability tests that guard the extracted presentation seams:

```bash
xcodebuildmcp macos test --project-path nexus.xcodeproj --scheme nexus \
  --extra-args -only-testing:nexusTests/RemoteClientPairingModelTests/workspaceBrowsePresentationStaysStableDuringTranscriptOnlyFocusedSessionUpdates \
  --extra-args -only-testing:nexusTests/RemoteClientPairingModelTests/workspaceBrowsePresentationStaysStableDuringPairedMacAvailabilityRefreshes \
  --extra-args -only-testing:nexusTests/RemoteClientPairingModelTests/focusedSessionWorkspaceLocationStaysStableDuringUnrelatedCatalogRefreshes
```

These tests do not replace SwiftUI Instruments, but they catch `Remote Client` browse/session observation broadening before you spend time in a profiling trace.

### Repeatable iPhone Remote Client trace fixture

For a deterministic iPhone `Remote Client` profiling pass, launch the app with `NEXUS_REMOTE_CLIENT_FIXTURE=invalidation-baseline` set in the iOS run scheme environment.

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
    "NEXUS_REMOTE_CLIENT_FIXTURE": "invalidation-baseline"
  }
}'
```

That fixture starts with:
- one active **Paired Mac** already selected and reachable
- a two-Workspace `Workspace Catalog` already available after refresh
- a launchable Pi structured **Session** in `Baseline API`
- automatic transcript-only focused `Session` updates after you open that conversation

Suggested trace path:
1. capture the home screen while tapping **Refresh** to exercise **Paired Mac** availability plus `Workspace Catalog` refreshes
2. open `Baseline API` → `Pi` → **Open conversation**
3. keep the trace running long enough to capture the automatic `Fixture update ...` activity appends on the structured `Session` surface

Important: `xcrun xctrace` currently reports `The SwiftUI instrument is not supported on the Simulator` for this app flow, so use the simulator fixture for deterministic navigation rehearsal and focused test validation, but run the final SwiftUI invalidation trace from Xcode Instruments on a physical iPhone.

## Profiling guidance

Use the automated baselines first. If a regression is user-visible, then profile the matching macOS app flow on the same machine and branch so the UI trace can be compared with the service baseline output above.

Keep captures comparable:

- use the same machine
- avoid running broad background work during captures
- compare the same audited flow, not a nearby path
- keep the baseline test iteration count unchanged unless you intentionally reset the baseline workflow
