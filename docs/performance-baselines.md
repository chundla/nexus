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

## Profiling guidance

Use the automated baselines first. If a regression is user-visible, then profile the matching macOS app flow on the same machine and branch so the UI trace can be compared with the service baseline output above.

Keep captures comparable:

- use the same machine
- avoid running broad background work during captures
- compare the same audited flow, not a nearby path
- keep the baseline test iteration count unchanged unless you intentionally reset the baseline workflow
