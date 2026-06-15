import Foundation
import NexusDomain
import Testing

@testable import NexusSessionPresentation

struct StructuredSessionFeedSegmentIterationPolicyTests {
    private func piFeedWithSegments() -> StructuredSessionFeedPresentation {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .status, text: "Session stream connected"),
                SessionActivityItem(kind: .message, text: "You: one", prompt: SessionPrompt(text: "one")),
                SessionActivityItem(kind: .message, text: "Pi: a"),
                SessionActivityItem(kind: .message, text: "You: two", prompt: SessionPrompt(text: "two")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Planning."),
                SessionActivityItem(kind: .message, text: "Pi: b"),
            ]
        )
        return structuredSessionFeedPresentation(for: screen)
    }

    @Test func progressiveRevealUsesFeedSegmentTailWhenSegmentsExist() throws {
        let feed = piFeedWithSegments()
        let segments = try #require(feed.feedSegments)
        #expect(segments.count == 5)

        let visible = try #require(
            structuredSessionVisibleFeedSegments(in: feed, visibleTailItemCount: 2)
        )
        #expect(visible.count == 2)
        #expect(visible.map(\.id) == Array(segments.suffix(2).map(\.id)))
    }

    @Test func synchronizedVisibleTailExpandsWhenFeedSegmentCountGrowsAfterInitialReveal() {
        let totalAfterTurn = 3
        let totalMidSession = 5
        #expect(
            StructuredSessionFeedSegmentRevealPolicy.synchronizedVisibleTailSegmentCount(
                currentVisibleCount: 3,
                totalFeedSegmentCount: totalAfterTurn
            ) == 3
        )
        #expect(
            StructuredSessionFeedSegmentRevealPolicy.synchronizedVisibleTailSegmentCount(
                currentVisibleCount: 3,
                totalFeedSegmentCount: totalMidSession
            ) == totalMidSession
        )
    }

    @Test func thinkingIndicatorStaysVisibleWhileOpenTurnHasReasoningContent() {
        let session = Session(
            id: UUID(),
            workspaceID: UUID(),
            providerID: .pi,
            isDefault: true,
            state: .ready
        )
        let screen = SessionScreen(
            session: session,
            primarySurface: .structuredActivityFeed,
            transcript: "",
            activityItems: [
                SessionActivityItem(kind: .message, text: "You: go", prompt: SessionPrompt(text: "go")),
                SessionActivityItem(kind: .status, text: "thoughts:", detailText: "Working."),
            ],
            isAgentTurnInProgress: true
        )
        #expect(
            structuredSessionThinkingIndicator(for: screen, hasPendingApprovalRequests: false)
                == StructuredSessionThinkingIndicator(text: "Thinking…")
        )
    }

    @Test func agentTurnDisclosureDefaultsKeepPerRowBubblesCollapsedWhileOpenTurnInProgress() {
        let reasoningID = UUID()
        let turn = StructuredSessionFeedAgentTurnSegment(
            id: UUID(),
            isOpen: true,
            stackItems: [
                .reasoning(
                    StructuredSessionFeedAgentTurnReasoningSegment(activityItemID: reasoningID, markdownBody: "Plan.")),
                .tool(StructuredSessionFeedAgentTurnToolSegment(activityItemID: UUID(), callPreview: "tool: run")),
            ],
            finalAnswer: nil
        )
        let defaults = structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn)
        #expect(defaults.tools == false)
        #expect(defaults.toolRows == [false])
    }

    @Test func agentTurnDisclosureDefaultsCollapseToolsWhenTurnComplete() {
        let toolID = UUID()
        let turn = StructuredSessionFeedAgentTurnSegment(
            id: UUID(),
            isOpen: false,
            stackItems: [
                .reasoning(
                    StructuredSessionFeedAgentTurnReasoningSegment(
                        activityItemID: UUID(), markdownBody: "Done thinking.")),
                .tool(StructuredSessionFeedAgentTurnToolSegment(activityItemID: toolID, callPreview: "bash: ls")),
            ],
            finalAnswer: StructuredSessionFeedAgentTurnFinalAnswerSegment(text: "ok", isStreaming: false)
        )
        let defaults = structuredSessionAgentTurnDisclosureExpansionDefaults(for: turn)
        #expect(defaults.tools == false)
        #expect(defaults.toolRows == [false])
    }
}
