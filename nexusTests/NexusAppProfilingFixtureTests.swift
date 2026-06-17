#if os(macOS)
    import Foundation
    import NexusSessionPresentation
    import Testing
    @testable import nexus

    @MainActor
    struct NexusAppProfilingFixtureTests {
        @Test func bootstrapStreamsDeterministicStructuredFeedProfilingBurstsOnMacOS() async throws {
            let model = try NexusAppModel.bootstrap(environment: [
                "NEXUS_MAC_PROFILE_FIXTURE": "structured-feed-profile"
            ])

            await model.refresh()
            let initialSelection = try #require(
                model.workspaceBrowseNavigationPresentation(currentWorkspaceID: nil).initialSelection)
            let sessionID: UUID =
                switch initialSelection {
                case .session(let sessionID):
                    sessionID
                case .workspace, .workspaceGroup:
                    Issue.record("Expected macOS profiling fixture to bootstrap directly into a Session selection")
                    throw CancellationError()
                }

            try await model.focusSession(sessionID: sessionID)
            for _ in 0..<40 where model.focusedStructuredSessionPresentation == nil {
                try await Task.sleep(nanoseconds: 25_000_000)
            }

            let initialPresentation = try #require(model.focusedStructuredSessionPresentation)

            #expect(initialPresentation.feed.activityRows.count >= 100)
            #expect(initialPresentation.feed.thinkingIndicator == StructuredSessionThinkingIndicator(text: "Thinking…"))
            #expect(model.focusedStructuredSessionDiagnosticSnapshot?.observation.isAgentTurnInProgress == true)

            for _ in 0..<40
            where model.focusedSessionScreen?.providerFacts.liveAssistantDraftText == nil {
                try await Task.sleep(nanoseconds: 25_000_000)
            }

            let expandedDraftText = try #require(model.focusedSessionScreen?.providerFacts.liveAssistantDraftText)
            #expect(expandedDraftText.isEmpty == false)

            for _ in 0..<40
            where model.focusedStructuredSessionPresentation?.feed.activityRows.last?.conversationPresentation?
                .isStreaming != true
            {
                try await Task.sleep(nanoseconds: 25_000_000)
            }

            let draftingBaselinePresentation = try #require(model.focusedStructuredSessionPresentation)
            let initialCommandCount = draftingBaselinePresentation.feed.activityRows.filter { $0.title == "Command" }
                .count

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
            let finalizedLatency = try #require(model.focusedStructuredSessionDiagnosticSnapshot?.finalOutputLatency)

            #expect(finalizedRow.text.hasPrefix("Pi: "))
            #expect(finalizedPresentation.feed.thinkingIndicator == nil)
            #expect(
                finalizedPresentation.feed.activityRows.count >= draftingBaselinePresentation.feed.activityRows.count
            )
            #expect(
                finalizedPresentation.feed.activityRows.filter { $0.title == "Command" }.count >= initialCommandCount
            )
            #expect(finalizedLatency.providerRuntimeLatencyMilliseconds > 0)
            #expect(finalizedLatency.serviceObservationLatencyMilliseconds != nil)

            // Regression for #208: during finalizedDwell (evil fixture churns providerFacts + finalOutputDiagnostic +
            // isAgentTurnInProgress + extensionUI notifications for autoScrollTrigger, while keeping activityItems
            // and isAgent stable), the focusedStructuredSessionPresentation (feed + autoScrollTrigger) and chrome
            // must not mutate. Live diagnostic values must still advance via the underlying screen.
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
                        "focusedStructuredSessionPresentation (incl. autoScrollTrigger + activityRowChunks) must not mutate on providerFacts/diagnostic/turn-progress churn when activityItems unchanged (#208)"
                    )
                }
                if let ch = model.focusedStructuredSessionChromePresentation, let stableCh = dwellStableChrome {
                    // Extension UI notifications may churn during dwell; row-affecting chrome fields must stay stable (#208).
                    #expect(ch.session == stableCh.session)
                    #expect(ch.isAgentTurnInProgress == stableCh.isAgentTurnInProgress)
                    #expect(ch.tokenUsage == stableCh.tokenUsage)
                    #expect(ch.slashCommands == stableCh.slashCommands)
                }
                dwellSamplesChecked += 1
            }
            #expect(dwellSamplesChecked > 0)

            for _ in 0..<240 {
                if model.focusedStructuredSessionPresentation?.feed.thinkingIndicator != nil,
                    model.focusedSessionScreen?.providerFacts.liveAssistantDraftText?.isEmpty == false
                {
                    break
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }

            #expect(model.focusedStructuredSessionPresentation?.feed.thinkingIndicator != nil)
            #expect(model.focusedSessionScreen?.providerFacts.liveAssistantDraftText?.isEmpty == false)
        }
    }
#endif
