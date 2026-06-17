import Foundation
import NexusSessionPresentation
import Testing

@testable import nexus

@MainActor
struct RemoteClientProfilingFixtureTests {
    @Test func bootstrapSeedsActivePairedMacAndWorkspaceCatalogForInvalidationProfiling() async throws {
        let model = RemoteClientPairingModel.bootstrap(environment: [
            "NEXUS_REMOTE_CLIENT_FIXTURE": "invalidation-baseline"
        ])

        let pairedMac = try #require(model.activePairedMac)
        #expect(pairedMac.name == "Profiling Mac")

        await model.refreshPairedMacAvailability()
        #expect(model.availability(for: pairedMac) == .available)

        await model.refreshActivePairedMacCatalog()
        let presentation = try #require(
            model.workspaceBrowsePresentation(showingGroupsOnly: false, selectedGroupID: nil as UUID?))

        #expect(
            presentation.workspaceOverviews.map { $0.workspace.name } == [
                "Baseline API",
                "Baseline iPhone",
            ])
    }

    @Test func bootstrapStreamsFocusedSessionUpdatesForInvalidationProfiling() async throws {
        let model = RemoteClientPairingModel.bootstrap(environment: [
            "NEXUS_REMOTE_CLIENT_FIXTURE": "invalidation-baseline"
        ])

        await model.refreshActivePairedMacCatalog()
        let session = try await model.launchOrResumeDefaultSession(
            workspaceID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            providerID: .pi
        )

        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedSessionScreen == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let initialScreen = try #require(model.focusedSessionScreen)
        #expect(initialScreen.transcript.contains("Pi shared Session stream connected"))

        for _ in 0..<30 where model.focusedSessionScreen?.transcript == initialScreen.transcript {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let updatedScreen = try #require(model.focusedSessionScreen)
        #expect(updatedScreen.session.id == session.id)
        #expect(updatedScreen.transcript.contains("Fixture update 1"))
        #expect(model.focusedSessionWorkspaceLocation == "Build Server • /srv/baseline-api")
    }

    @Test func bootstrapStreamsThinkingDiagnosticSnapshotsForLongObservationProfiling() async throws {
        let model = RemoteClientPairingModel.bootstrap(environment: [
            "NEXUS_REMOTE_CLIENT_FIXTURE": "thinking-diagnosis"
        ])

        await model.refreshActivePairedMacCatalog()
        let session = try await model.launchOrResumeDefaultSession(
            workspaceID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            providerID: .pi
        )

        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)

        for _ in 0..<20 where model.focusedStructuredSessionDiagnosticSnapshot == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let initialSnapshot = try #require(model.focusedStructuredSessionDiagnosticSnapshot)
        #expect(initialSnapshot.observation.isAgentTurnInProgress)
        #expect(initialSnapshot.presentation?.hasThinkingIndicator == true)

        for _ in 0..<30
        where model.focusedStructuredSessionDiagnosticSnapshot?.observation.lastActivityItemText
            == initialSnapshot.observation.lastActivityItemText
        {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let updatedSnapshot = try #require(model.focusedStructuredSessionDiagnosticSnapshot)
        #expect(
            updatedSnapshot.observation.transcriptCharacterCount > initialSnapshot.observation.transcriptCharacterCount)
        #expect(
            updatedSnapshot.presentation?.activityRowCount ?? 0 > initialSnapshot.presentation?.activityRowCount ?? 0)
        #expect(updatedSnapshot.presentation?.hasThinkingIndicator == true)
        #expect(updatedSnapshot.observation.lastActivityItemText?.contains("Pi: thinking step") == true)
    }

    @Test func bootstrapCapturesFinalOutputLatencyDiagnosticSnapshotsForRemoteClientProfiling() async throws {
        let model = RemoteClientPairingModel.bootstrap(environment: [
            "NEXUS_REMOTE_CLIENT_FIXTURE": "invalidation-baseline"
        ])

        await model.refreshActivePairedMacCatalog()
        let session = try await model.launchOrResumeDefaultSession(
            workspaceID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            providerID: .pi
        )

        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)
        for _ in 0..<20 where model.focusedStructuredSessionDiagnosticSnapshot == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        try await model.takeFocusedRemoteSessionControl(columns: 44, rows: 12)
        try await model.sendInputToFocusedRemoteSession("ship it")

        let snapshot = try #require(model.focusedStructuredSessionDiagnosticSnapshot)
        let finalOutputLatency = try #require(snapshot.finalOutputLatency)
        #expect(finalOutputLatency.providerRuntimeLatencyMilliseconds == 4)
        #expect(finalOutputLatency.serviceObservationLatencyMilliseconds == 10)
        #expect(finalOutputLatency.isVisibleInPresentation)
        #expect(finalOutputLatency.visibleActivityRowText == "Pi: Fixture reply for: ship it")
    }

    @Test func bootstrapStreamsDeterministicStructuredFeedProfilingBursts() async throws {
        let model = RemoteClientPairingModel.bootstrap(environment: [
            "NEXUS_REMOTE_CLIENT_FIXTURE": "streaming-feed-profile"
        ])

        await model.refreshActivePairedMacCatalog()
        let session = try await model.launchOrResumeDefaultSession(
            workspaceID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            providerID: .pi
        )

        await model.focusRemoteSession(sessionID: session.id, workspaceID: session.workspaceID)
        for _ in 0..<40 where model.focusedStructuredSessionPresentation == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let initialPresentation = try #require(model.focusedStructuredSessionPresentation)
        let initialRow = try #require(initialPresentation.feed.activityRows.last)
        let initialCommandCount = initialPresentation.feed.activityRows.filter { $0.title == "Command" }.count

        #expect(initialPresentation.feed.activityRows.count >= 100)
        #expect(initialPresentation.feed.thinkingIndicator == StructuredSessionThinkingIndicator(text: "Thinking…"))
        #expect(model.focusedStructuredSessionDiagnosticSnapshot?.observation.isAgentTurnInProgress == true)

        for _ in 0..<40 where model.focusedSessionScreen?.providerFacts.liveAssistantDraftText == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let expandedDraftText = try #require(model.focusedSessionScreen?.providerFacts.liveAssistantDraftText)
        #expect(expandedDraftText.isEmpty == false)

        for _ in 0..<120
        where model.focusedStructuredSessionDiagnosticSnapshot?.observation.isAgentTurnInProgress != false {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        for _ in 0..<40
        where model.focusedStructuredSessionPresentation?.feed.thinkingIndicator != nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let finalizedPresentation = try #require(model.focusedStructuredSessionPresentation)
        let finalizedRow = try #require(finalizedPresentation.feed.activityRows.last)

        // Regression for #208: during finalizedDwell (evil fixture churns providerFacts + finalOutputDiagnostic +
        // isAgentTurnInProgress + extensionUI notifications for autoScrollTrigger, while keeping activityItems
        // and isAgent stable), the focusedStructuredSessionPresentation (feed + autoScrollTrigger) and chrome
        // must not mutate on the Remote Client path. Live diagnostic values must still advance via the underlying screen.
        // Sample immediately after turn finalization (while still in the post-turn dwell window) to match
        // the macOS NexusAppProfilingFixtureTests structure and the actual dwell duration (~1 s).
        let dwellStablePresentation = finalizedPresentation
        let dwellStableChrome = model.focusedStructuredSessionChromePresentation
        let dwellStableRowID = finalizedRow.id
        var dwellSamplesChecked = 0
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 35_000_000)
            if let snap = model.focusedStructuredSessionDiagnosticSnapshot,
                snap.observation.isAgentTurnInProgress
            {
                break
            }
            if let p = model.focusedStructuredSessionPresentation {
                #expect(p.feed.activityRows.last?.id == dwellStableRowID, "rows must stay stable in dwell")
                #expect(
                    p == dwellStablePresentation,
                    "focusedStructuredSessionPresentation (incl. autoScrollTrigger + activityRowChunks) must not mutate on providerFacts/diagnostic/turn-progress churn when activityItems unchanged (#208) on Remote Client path"
                )
            }
            if let ch = model.focusedStructuredSessionChromePresentation, let stableCh = dwellStableChrome {
                #expect(ch.session == stableCh.session)
                #expect(ch.isAgentTurnInProgress == stableCh.isAgentTurnInProgress)
                #expect(ch.tokenUsage == stableCh.tokenUsage)
                #expect(ch.slashCommands == stableCh.slashCommands)
            }
            dwellSamplesChecked += 1
        }
        #expect(dwellSamplesChecked > 0)

        // After dwell sampling (and any remaining dwell ticks), ensure the final-output latency sample is visible
        // in presentation, then capture and assert its fields. This mirrors the original Remote Client test intent
        // while keeping the #208 stability check in the correct temporal window.
        for _ in 0..<40
        where model.focusedStructuredSessionDiagnosticSnapshot?.finalOutputLatency?.isVisibleInPresentation != true {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let finalizedSnapshot = try #require(model.focusedStructuredSessionDiagnosticSnapshot)
        let finalOutputLatency = try #require(finalizedSnapshot.finalOutputLatency)

        #expect(finalizedRow.text.hasPrefix("Pi: "))
        #expect(finalizedPresentation.feed.thinkingIndicator == nil)
        #expect(finalizedPresentation.feed.activityRows.count == initialPresentation.feed.activityRows.count + 1)
        #expect(
            finalizedPresentation.feed.activityRows.filter { $0.title == "Command" }.count == initialCommandCount + 1)
        #expect(finalOutputLatency.providerRuntimeLatencyMilliseconds > 0)
        #expect(finalOutputLatency.serviceObservationLatencyMilliseconds != nil)

        for _ in 0..<160 {
            if let snapshot = model.focusedStructuredSessionDiagnosticSnapshot,
                snapshot.observation.isAgentTurnInProgress,
                model.focusedSessionScreen?.providerFacts.liveAssistantDraftText != nil
            {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(model.focusedStructuredSessionDiagnosticSnapshot?.observation.isAgentTurnInProgress == true)
        #expect(model.focusedSessionScreen?.providerFacts.liveAssistantDraftText?.isEmpty == false)
    }
}
