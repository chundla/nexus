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
        let initialSelection = try #require(model.workspaceBrowseNavigationPresentation(currentWorkspaceID: nil).initialSelection)
        let sessionID: UUID = switch initialSelection {
        case .session(let sessionID):
            sessionID
        case .workspace, .workspaceGroup:
            Issue.record("Expected macOS profiling fixture to bootstrap directly into a Session selection")
            throw CancellationError()
        }

        try await model.focusSession(sessionID: sessionID)
        for _ in 0 ..< 40 where model.focusedStructuredSessionPresentation == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let initialPresentation = try #require(model.focusedStructuredSessionPresentation)
        let initialRow = try #require(initialPresentation.feed.activityRows.last)
        let initialCommandCount = initialPresentation.feed.activityRows.filter { $0.title == "Command" }.count

        #expect(initialPresentation.feed.activityRows.count >= 100)
        #expect(initialPresentation.feed.thinkingIndicator == StructuredSessionThinkingIndicator(text: "Thinking…"))
        #expect(initialRow.conversationPresentation?.isStreaming == true)

        for _ in 0 ..< 40 where model.focusedStructuredSessionPresentation?.feed.activityRows.last?.text == initialRow.text {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let expandedDraftRow = try #require(model.focusedStructuredSessionPresentation?.feed.activityRows.last)
        #expect(expandedDraftRow.id == initialRow.id)
        #expect(expandedDraftRow.conversationPresentation?.isStreaming == true)
        #expect(expandedDraftRow.text != initialRow.text)

        for _ in 0 ..< 80 where model.focusedStructuredSessionDiagnosticSnapshot?.observation.isAgentTurnInProgress != false {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let finalizedPresentation = try #require(model.focusedStructuredSessionPresentation)
        let finalizedRow = try #require(finalizedPresentation.feed.activityRows.last)
        let finalizedLatency = try #require(model.focusedStructuredSessionDiagnosticSnapshot?.finalOutputLatency)

        #expect(finalizedRow.id == initialRow.id)
        #expect(finalizedRow.conversationPresentation?.isStreaming == false)
        #expect(finalizedPresentation.feed.thinkingIndicator == nil)
        #expect(finalizedPresentation.feed.activityRows.count == initialPresentation.feed.activityRows.count + 1)
        #expect(finalizedPresentation.feed.activityRows.filter { $0.title == "Command" }.count == initialCommandCount + 1)
        #expect(finalizedLatency.providerRuntimeLatencyMilliseconds > 0)
        #expect(finalizedLatency.serviceObservationLatencyMilliseconds != nil)

        for _ in 0 ..< 80 {
            if let snapshot = model.focusedStructuredSessionDiagnosticSnapshot,
               let row = model.focusedStructuredSessionPresentation?.feed.activityRows.last,
               snapshot.observation.isAgentTurnInProgress,
               row.id != initialRow.id,
               row.conversationPresentation?.isStreaming == true {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let nextDraftRow = try #require(model.focusedStructuredSessionPresentation?.feed.activityRows.last)
        #expect(nextDraftRow.id != initialRow.id)
        #expect(nextDraftRow.conversationPresentation?.isStreaming == true)
        #expect(model.focusedStructuredSessionDiagnosticSnapshot?.observation.isAgentTurnInProgress == true)
    }
}
#endif
